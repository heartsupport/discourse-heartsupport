# name: discourse-supported
# about: Mark topics as supported when they've reached a certain threshold
# version: 0.1.3
# authors: Thomas Hart II, Acacia Bengo Ssembajjwe
# url: https://github.com/myrridin/discourse-supported

after_initialize do
  class ::Post
    after_create :check_for_support
    after_create :check_for_support_response

    SUPPORT_CATEGORIES = [67, 77, 85, 87, 88, 89, 4]
    ASK_CATEGORIES = [67, 89, 4]
    SUPPORT_LIMIT = 500
    ASK_USER_LIMIT = 300

    def check_for_support
      needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")
      supported_tag = Tag.find_or_create_by(name: "Supported")
      supplier_url = URI("https://porter.heartsupport.com/webhooks/supplier")

      return unless SUPPORT_CATEGORIES.include?(topic.category_id)

      if is_first_post?
        # If it's the first post, add the needs support tag
        topic.tags << needs_support_tag
        topic.custom_fields["needs_support"] = true
        topic.custom_fields["supported"] = false
        supported = false
      end

      if !is_first_post?
        supported = topic.custom_fields["supported"] || !topic.tags.include?(needs_support_tag)
        newly_supported = false

        unless supported
          # count reply word count
          word_count = topic.posts.sum(:word_count)
          reply_count = topic.posts_count - 1

          if reply_count >= 1
            if word_count >= SUPPORT_LIMIT
              # remove needs support tag
              topic.tags.delete needs_support_tag
              topic.custom_fields["supported"] = true
              supported = true
              newly_supported = true
              topic.tags << supported_tag if ASK_CATEGORIES.include?(topic.category_id)
            end
          end

          topic.save!
        end

        Rails.logger.info("POSTING TO HSAPPS")
        uri = URI("https://porter.heartsupport.com/twilio/discourse_webhook")
        Net::HTTP.post_form(
          uri,
          topic_id: topic_id, supported: supported,
          newly_supported: newly_supported,
          body: cooked, username: user.username,
        )
      end

      Rails.logger.info("CHECKING FOR SUPPORT ON #{self}")

      # send webhook request to supplier
      Rails.logger.info("POSTING TO SUPPLIER")
      # make an API call to create a supplier topic
      Net::HTTP.post_form(
        supplier_url,
        topic_id: topic_id,
        supported: supported,
        username: user.username,
        category_id: topic.category_id,
        closed: topic.closed,
      )
    end

    def check_for_support_response
      # define the system user
      system_user = User.find_by(username: "system")
      # check if private message response and text is YES or NO

      if topic.archetype == Archetype.private_message && topic.title == "Follow Up on Your Recent Post"
        user_message = raw.downcase&.strip
        ref_topic = Topic.find_by(id: topic.custom_fields["ref_topic_id"])
        case user_message
        when "yes"
          if ref_topic
            needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")
            supported_tag = Tag.find_or_create_by(name: "Supported")
            staff_escalation_tag = Tag.find_or_create_by(name: "Staff-Escalation")
            asked_user_tag = Tag.find_or_create_by(name: "Asked-User")

            ref_topic.tags.delete needs_support_tag
            ref_topic.tags.delete staff_escalation_tag
            ref_topic.tags.delete asked_user_tag

            ref_topic.tags << supported_tag unless ref_topic.tags.include?(supported_tag)
            ref_topic.custom_fields["supported"] = true
            ref_topic.save!
          end

          # send reply to user

          Post.create!(
            topic_id: topic.id,
            user_id: system_user.id,
            raw: "Hi #{ref_topic.user.username}, what helped?",
          )

          # send a DM thanking repliers
          repliers = ref_topic.posts.map(&:user).uniq - [ref_topic.user]
          dm_params = {
            title: "You helped a user!",
            raw: "A user you supported named #{ref_topic.user.username} said that your replies " \
            "helped them feel cared for. Thank you so much for offering support " \
            "to them. It's making a real difference. If you want to check out the " \
            "topic you can find it here: #{ref_topic.url}",
            archetype: Archetype.private_message,
            target_usernames: repliers.map(&:username),
          }
          # send DM to repliers
          PostCreator.create!(system_user, dm_params)
        when "no"
          if ref_topic
            staff_escalation_tag = Tag.find_or_create_by(name: "Staff-Escalation")
            supported_tag = Tag.find_or_create_by(name: "Supported")
            ref_topic.tags.delete supported_tag
            ref_topic.tags << staff_escalation_tag unless ref_topic.tags.include?(staff_escalation_tag)
            ref_topic.custom_fields["staff_escalation"] = true
            ref_topic.save!
          end
          # staff_escalation_tag = Tag.find_or_create_by(name: "Staff-Escalation")
          # topic.tags << staff_escalation_tag unless topic.tags.include?(staff_escalation_tag)
          # topic.custom_fields["staff_escalation"] = true
          # topic.save!

          Post.create!(
            topic_id: topic.id,
            user_id: system_user.id,
            raw: "Hi #{ref_topic.user.username}, I'm sorry to hear that you didn't feel supported. What do you need?",
          )
        else
          # if staff escalation is true and supported is false then post a whisper
          if ref_topic.custom_fields["staff_escalation"]
            # create a whisper
            whisper_params = {
              topic_id: ref_topic.id,
              post_type: Post.types[:whisper],
              raw: user_message,
            }
            PostCreator.create!(system_user, whisper_params)
          end
        end
      end
    end
  end

  # add job that runs everyday to ask users if they feel supported
  class ::Jobs::FollowUpSupport < Jobs::Scheduled
    ASK_CATEGORIES = [67, 89, 4]
    ASK_USER_LIMIT = 300
    every 1.day

    def execute(args)
      # needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")
      supported_tag = Tag.find_or_create_by(name: "Supported")
      # query all all topics created > 24 hours, does not have a supported tag, and don't have an asked user tag
      topics = Topic
        .where("topics.created_at < ? AND topics.created_at > ?", 24.hours.ago, 14.days.ago)
        .where("topics.archetype = ?", "regular")
        .where("topics.posts_count > ?", 1)
        .where("topics.word_count >= ?", ASK_USER_LIMIT)
        .where("topics.category_id IN (?)", ASK_CATEGORIES)
        .joins("INNER JOIN topic_tags ON topic_tags.topic_id = topics.id")
        .where("topic_tags.tag_id != ?", supported_tag.id)
        .joins("INNER JOIN topic_custom_fields ON topic_custom_fields.topic_id = topics.id")
        .where("topic_custom_fields.name = ?", "asked_user")

      topics.each do |topic|
        next if topic.custom_fields["asked_user"].present?
        # send a message to the user asking if they feel supported
        require_dependency "post_creator"
        system_user = User.find_by(username: "system")

        dm_params = {
          title: "Follow Up on Your Recent Post",
          raw: "Hi #{topic.user.username}, On this topic you posted, did you get the advice " \
          "you needed? \n #{topic.url} \n" \
          "Reply to this message with YES if you feel supported, or NO if you don't.",
          archetype: Archetype.private_message,
          target_usernames: [topic.user.username],
          custom_fields: { ref_topic_id: topic.id },
        }
        PostCreator.create!(system_user, dm_params)
        topic.custom_fields["asked_user"] = "true"
        topic.save!
      end
    end
  end
end
