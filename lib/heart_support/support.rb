module HeartSupport
  module Support
    SUPPORT_CATEGORIES = [67, 77, 85, 87, 88, 89]
    ASK_CATEGORIES = [67, 89]
    SUPPORT_LIMIT = 500
    ASK_USER_LIMIT = 300

    def self.check_support(post)
      topic = post.topic
      category_id = topic.category_id
      user = post.user

      needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")
      # supported_tag = Tag.find_or_create_by(name: "Supported")
      supplier_url = URI("https://porter.heartsupport.com/webhooks/supplier")
      # sufficient_words_tag = Tag.find_or_create_by(name: "Sufficient-Words")

      return unless SUPPORT_CATEGORIES.include?(category_id)

      if post.is_first_post?
        # If it's the first post, add the needs support tag
        topic.tags << needs_support_tag
        topic.custom_fields["needs_support"] = true
        topic.custom_fields["supported"] = false
        supported = false
      end

      if !post.is_first_post?
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
              # topic.custom_fields["supported"] = true
              supported = false
              newly_supported = false
              # topic.tags << supported_tag if ASK_CATEGORIES.include?(topic.category_id)
              # topic.tags << sufficient_words_tag unless topic.tags.include?(sufficient_words_tag)
            end
          end

          topic.save!
        end

        Rails.logger.info("POSTING TO HSAPPS")
        uri = URI("https://porter.heartsupport.com/twilio/discourse_webhook")
        Net::HTTP.post_form(
          uri,
          topic_id: topic.id, supported: supported,
          newly_supported: newly_supported,
          body: post.cooked, username: user.username,
        )
      end

      Rails.logger.info("CHECKING FOR SUPPORT ON #{self}")

      # send webhook request to supplier
      Rails.logger.info("POSTING TO SUPPLIER")
      # make an API call to create a supplier topic
      Net::HTTP.post_form(
        supplier_url,
        topic_id: topic.id,
        supported: supported,
        username: user.username,
        category_id: topic.category_id,
        closed: topic.closed,
      )
    end

    def self.check_response(post)
      topic = post.topic

      # define the system user
      system_user = User.find_by(username: "system")
      # check if private message response and text is YES or NO

      if topic.archetype == Archetype.private_message && topic.title == "Follow Up on Your Recent Post"
        user_message = post.raw.downcase&.strip
        ref_topic = Topic.find_by(id: topic.custom_fields["ref_topic_id"])
        case user_message
        when "yes"
          if ref_topic
            needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")
            supported_tag = Tag.find_or_create_by(name: "Supported")
            staff_escalation_tag = Tag.find_or_create_by(name: "Staff-Escalation")
            asked_user_tag = Tag.find_or_create_by(name: "Asked-User")
            user_answered_tag = Tag.find_or_create_by(name: "User-Answered")

            ref_topic.tags.delete needs_support_tag
            ref_topic.tags.delete staff_escalation_tag
            ref_topic.tags.delete asked_user_tag

            ref_topic.tags << supported_tag unless ref_topic.tags.include?(supported_tag)
            ref_topic.tags << user_answered_tag unless ref_topic.tags.include?(user_answered_tag)
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
          thank_repliers(ref_topic)
        when "no"
          if ref_topic
            staff_escalation_tag = Tag.find_or_create_by(name: "Staff-Escalation")
            supported_tag = Tag.find_or_create_by(name: "Supported")
            ref_topic.tags.delete supported_tag
            ref_topic.tags << staff_escalation_tag unless ref_topic.tags.include?(staff_escalation_tag)
            ref_topic.custom_fields["staff_escalation"] = true
            ref_topic.save!
          end

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

            # push this to porter
            Net::HTTP.post_form(
              URI("https://porter.heartsupport.com/webhooks/followup"),
              topic_id: ref_topic.id,
              message: user_message,
            )
          end
        end
      end
    end

    def self.thank_repliers(topic)
      # return if the topic is closed, unlisted, or archived
      return if topic.closed || topic.archived || !topic.visible

      # find system user
      system_user = User.find_by(username: "system")

      repliers = topic.posts
        .where.not(user_id: [topic.user_id, system_user.id])
        .where("notify_moderators_count = ?", 0)
        .where("deleted_at IS NULL")
        .map(&:user)
        .pluck(:username)

      repliers.each do |username|
        dm_params = {
          title: "You helped a user!",
          raw: "A user you supported named #{topic.user.username} said that your replies " \
          "helped them feel cared for. Thank you so much for offering support " \
          "to them. It's making a real difference. If you want to check out the " \
          "topic you can find it here: #{topic.url}",
          archetype: Archetype.private_message,
          target_usernames: [username],
        }
        # send DM to repliers
        PostCreator.create!(system_user, dm_params)
      end
    end
  end
end
