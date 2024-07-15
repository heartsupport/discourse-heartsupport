module HeartSupport
  RESOLUTION_HIERARCHY = [
    { tag: "User-Answered-Yes", priority: 7 },
    { tag: "User-Selected", priority: 6 },
    { tag: "User-Answered-No", priority: 5 },
    { tag: "Admin-Selected", priority: 4 },
    { tag: "Sufficient-Words", priority: 3 },
    { tag: "Trained-Reply", priority: 2 },
    { tag: "Insufficient", priority: 1 },
    { tag: "Needs-Support", priority: 0 }
  ]

  def self.set_resolution_tag(topic, tag_name)
    forum_tag =
      HeartSupport::RESOLUTION_HIERARCHY.find do |forum_tag|
        forum_tag[:tag] == tag_name
      end

    if forum_tag
      tag_name = forum_tag[:tag]
      priority = forum_tag[:priority]

      # find all tags with lower prioty and remove them
      lower_priority_tags =
        HeartSupport::RESOLUTION_HIERARCHY.select do |tag|
          tag[:priority] < priority
        end
      lower_priority_tags.each do |tag|
        the_tag = Tag.find_by(name: tag[:tag])
        if topic.tags.include?(the_tag)
          topic.tags.delete(Tag.find_by(name: tag[:tag]))
        end
      end

      higher_priority_tags =
        HeartSupport::RESOLUTION_HIERARCHY.select do |tag|
          tag[:priority] > priority
        end

      if higher_priority_tags.blank?
        # add the tag
        the_tag = Tag.find_or_create_by(name: tag_name)
        topic.tags << the_tag unless topic.tags.include?(the_tag)
      end

      # save the topic
      topic.save
    end
  end

  def self.add_topic_tags(topic, tag_name)
    tag = Tag.find_by(name: tag_name)
    if tag && topic.tags.exclude?(tag)
      topic.tags << tag
      topic.save
    end
  end

  def self.remove_topic_tags(topic, tag_name)
    tag = Tag.find_by(name: tag_name)
    if tag && topic.tags.include?(tag)
      topic.tags.delete(tag)
      topic.save
    end
  end

  module Support
    SUPPORT_CATEGORIES = [67, 77, 85, 87, 88, 89, 102, 106]
    ASK_CATEGORIES = [67, 89]
    SUPPORT_LIMIT = 500
    ASK_USER_LIMIT = 300
    STAFF_GROUPS = [3, 42, 73]

    def self.check_response(post)
      topic = post.topic

      # define the system user
      system_user = User.find_by(username: "system")
      # check if private message response and text is YES or NO

      if topic.archetype == Archetype.private_message &&
           topic.title == "Follow Up on Your Recent Post" &&
           post.user_id != system_user.id
        user_message = post.raw.downcase&.strip
        ref_topic = Topic.find_by(id: topic.custom_fields["ref_topic_id"])
        case user_message
        when "yes"
          if ref_topic
            # remove staff escalation tag
            HeartSupport.remove_topic_tags(ref_topic, "Staff-Escalation")
            #
            # remove asked user tag
            HeartSupport.remove_topic_tags(ref_topic, "Asked-User")

            # add supported tag
            HeartSupport.add_topic_tags(ref_topic, "Supported")

            # set resolution tag as user answered yes
            HeartSupport.set_resolution_tag(ref_topic, "User-Answered-Yes")

            ref_topic.custom_fields["supported"] = true
            ref_topic.save
          end

          response =
            "Thank you for your feedback! \n" \
              "Click on the form and answer the one question because it will help us know specifically what helped: " \
              "<a href='https://docs.google.com/forms/d/e/1FAIpQLScrXmJ96G3l4aypDtf307JycIhFHS9_8WMkF65m9JiM9Xm6WA/viewform' target='_blank'>
          https://docs.google.com/forms/d/e/1FAIpQLScrXmJ96G3l4aypDtf307JycIhFHS9_8WMkF65m9JiM9Xm6WA/viewform
          </a> \n"

          Post.create!(
            topic_id: topic.id,
            user_id: system_user.id,
            raw: response
          )

          # send a DM thanking repliers
          thank_repliers(ref_topic)
        when "no"
          if ref_topic
            # remove the supported tag
            HeartSupport.remove_topic_tags(ref_topic, "Supported")

            # add staff escalation tag
            HeartSupport.add_topic_tags(ref_topic, "Staff-Escalation")

            # remove the asked user tag
            HeartSupport.remove_topic_tags(ref_topic, "Asked-User")

            # add resolution tag as user answered no
            HeartSupport.add_resolution_tag(ref_topic, "User-Answered-No")

            ref_topic.custom_fields["staff_escalation"] = true
            ref_topic.save!
          end

          response =
            "Thank you for sharing that with us. We'll get you more support. \n" \
              "Click on the form and answer the one question because it will help us know how we can improve: " \
              "<a href='https://docs.google.com/forms/d/e/1FAIpQLSdxWbRMQPUe0IxL0xBEDA5RZ5B0a9Yl2e25ltW5RGDE6J2DOA/viewform' target='_blank'>https://docs.google.com/forms/d/e/1FAIpQLSdxWbRMQPUe0IxL0xBEDA5RZ5B0a9Yl2e25ltW5RGDE6J2DOA/viewform</a>"

          Post.create!(
            topic_id: topic.id,
            user_id: system_user.id,
            raw: response
          )
        else
          # if staff escalation is true and supported is false then post a whisper
          if ref_topic.custom_fields["staff_escalation"]
            # create a whisper
            whisper_params = {
              topic_id: ref_topic.id,
              post_type: Post.types[:whisper],
              raw: user_message
            }
            PostCreator.create!(system_user, whisper_params)

            # push this to porter
            Net::HTTP.post_form(
              URI("https://porter.heartsupport.com/webhooks/followup"),
              dm_id: topic.id,
              topic_id: ref_topic.id,
              message: user_message,
              discourse_user_id: post.user_id,
              response:
                ref_topic.tags.include?(user_answered_yes_tag) ? "yes" : "no"
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

      repliers =
        topic
          .posts
          .where.not(user_id: [topic.user_id, system_user.id])
          .where("notify_moderators_count = ?", 0)
          .where("deleted_at IS NULL")
          .map(&:user)
          .pluck(:username)

      repliers.each do |username|
        dm_params = {
          title: "You helped a user!",
          raw:
            "A user you supported named #{topic.user.username} said that your replies " \
              "helped them feel cared for. Thank you so much for offering support " \
              "to them. It's making a real difference. If you want to check out the " \
              "topic you can find it here: #{topic.url}",
          archetype: Archetype.private_message,
          target_usernames: [username]
        }
        # send DM to repliers
        PostCreator.create!(system_user, dm_params)
      end
    end

    def self.update_tags(post)
      topic = post.topic
      user = post.user
      if user.staff?
        # remove the staff escalation tag
        HeartSupport.remove_topic_tags(topic, "Staff-Escalation")

        # DM user to ask for feedback
        require_dependency "post_creator"
        system_user = User.find_by(username: "system")

        message_text =
          "Hi #{topic.user.username}, \n" \
            "On this topic you posted, did you get the support you needed? \n " \
            "#{topic.url} \n" \
            "Reply to this message with YES if you feel supported, or NO if you don't."

        dm_params = {
          title: "Follow Up on Your Recent Post",
          raw: message_text,
          archetype: Archetype.private_message,
          target_usernames: [topic.user.username],
          custom_fields: {
            ref_topic_id: topic.id
          }
        }
        PostCreator.create!(system_user, dm_params)
        topic.custom_fields["asked_user"] = "true"

        HeartSupport.add_topic_tags(topic, "Asked-User")

        topic.save!
      end
    end

    def self.process_post(post)
      topic = post.topic
      category_id = topic.category_id
      user = post.user

      # return if the topic category is not in the support categories
      return unless SUPPORT_CATEGORIES.include?(category_id)

      # check if the first post as a topic or a reply
      if post.is_first_post?
        # add the needs support tag
        HeartSupport.add_topic_tags(topic, "Needs-Support")
        topic.custom_fields["needs_support"] = true
        topic.custom_fields["supported"] = false
        supported = false
        newly_supported = false
        topic.save
      end

      if !post.is_first_post?
        reply_count = topic.posts.where.not(user_id: topic.user_id).count
        word_count =
          topic.posts.where.not(user_id: topic.user_id).sum(:word_count)

        supported = topic.tags.include?(supported_tag)
        # # when already supported
        # if supported
        # end
        #
        #when not supported
        if !supported
          # when word counts > 500
          # remove needs support tag, add sufficient words tag and
          # supported tag and remove all other resolution tags
          if word_count >= SUPPORT_LIMIT && reply_count >= 1
            # add sufficient words tag
            HeartSupport.set_resolution_tag(topic, "Sufficient-Words")

            # add supported tag
            # set resolution tag as supported
            HeartSupport.set_resolution_tag(topic, "Supported")
            newly_supported = true
            supported = true
            topic.custom_fields["supported"] = true

            topic.save
          end

          # when word counts < 500
          if word_count < SUPPORT_LIMIT
            # if replier is a staff member or surge-replier, then add trained_replier tag
            if user.primary_group_id == 73 || user.primary_group_id == 42
              # set the trained replier tag
              HeartSupport.set_resolution_tag(topic, "Trained-Reply")
            end

            # if repler is a SWAT member and the second then set trained replier tag too
            if user.primary_group_id == 54
              swat_repliers =
                topic
                  .posts
                  .joins(:user)
                  .where(users: { primary_group_id: 54 })
                  .count
              if swat_repliers >= 2
                # set the trained replier tag
                HeartSupport.set_resolution_tag(topic, "Trained-Reply")
              end
            end
          end
        end
      end

      # send webhook request to supplier
      send_supplier_webhook(
        topic.id,
        supported,
        user.username,
        category_id,
        topic.closed
      )
      # send a webhook to discourse
      send_discourse_webhook(
        topic.id,
        supported,
        newly_supported,
        post.cooked,
        user.username
      )
    end

    def send_discourse_webhook(
      topic_id,
      supported,
      newly_supported,
      body,
      username
    )
      Rails.logger.info("POSTING TO HSAPPS")
      url = "https://porter.heartsupport.com/twilio/discourse_webhook"
      hsapps_url = URI(url)
      Net::HTTP.post_form(
        hsapps_url,
        topic_id: topic_id,
        supported: supported,
        newly_supported: newly_supported,
        body: body,
        username: username
      )
    end

    def send_supplier_webhook(
      topic_id,
      supported,
      username,
      category_id,
      closed
    )
      # send webhook request to supplier
      Rails.logger.info("POSTING TO SUPPLIER")

      url = "https://porter.heartsupport.com/webhooks/supplier"
      supplier_url = URI(url)

      # make an API call to create a supplier topic
      Net::HTTP.post_form(
        supplier_url,
        topic_id: topic_id,
        supported: supported,
        username: username,
        category_id: category_id,
        closed: closed
      )
    end
  end

  module Tags
    PLATFORM_TOPICS_CATEGORIES = [77, 87, 102, 106, 85, 89]
    ASK_CATEGORIES = [67, 89, 4]
    def self.process_tags(topic_tag)
      # when video reply tag is added
      #
      #when user-selected tag is added
      #
      #
      #when admin selected tag is added
      #
      #
    end

    def self.tag_video_reply(topic_tag)
      video_reply_tag = Tag.find_or_create_by(name: "Video-Reply")
      needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")
      supported_tag = Tag.find_or_create_by(name: "Supported")
      asked_user_tag = Tag.find_or_create_by(name: "Asked-User")
      sufficient_words_tag = Tag.find_or_create_by(name: "Sufficient-Words")

      if topic_tag.tag_id == video_reply_tag.id
        topic = Topic.find_by(id: topic_tag.topic_id)
        topic.tags.delete needs_support_tag
        # changed implementation & not adding supported tag when video-reply tag is added
        # topic.tags << supported_tag unless topic.tags.include?(supported_tag)
        unless topic.tags.include?(sufficient_words_tag)
          topic.tags << sufficient_words_tag
        end
        topic.save!

        if ASK_CATEGORIES.include?(topic.category_id)
          # send user follow up message
          require_dependency "post_creator"
          system_user = User.find_by(username: "system")

          message_text =
            "Hi #{topic.user.username}, \n" \
              "On this topic you posted, did you get the support you needed? \n " \
              "#{topic.url} \n" \
              "Reply to this message with YES if you feel supported, or NO if you don't."

          dm_params = {
            title: "Follow Up on Your Recent Post",
            raw: message_text,
            archetype: Archetype.private_message,
            target_usernames: [topic.user.username],
            custom_fields: {
              ref_topic_id: topic.id
            }
          }
          PostCreator.create!(system_user, dm_params)
          topic.custom_fields["asked_user"] = "true"
          unless topic.tags.include?(asked_user_tag)
            topic.tags << asked_user_tag
          end
          topic.save!
        end
      end
    end

    def self.tag_platform_topic(topic)
      need_listening_ear_tag = Tag.find_or_create_by(name: "Need-Listening-Ear")

      if PLATFORM_TOPICS_CATEGORIES.include?(topic.category_id)
        unless topic.tags.include?(need_listening_ear_tag)
          topic.tags << need_listening_ear_tag
        end
        topic.save!
      end
    end
  end
end
