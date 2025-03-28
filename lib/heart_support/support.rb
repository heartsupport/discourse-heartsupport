module HeartSupport
  RESOLUTION_HIERARCHY = [
    { tag: "User-Answered-Yes", priority: 7 },
    { tag: "User-Selected", priority: 6 },
    { tag: "User-Answered-No", priority: 5 },
    { tag: "Admin-Selected", priority: 4 },
    { tag: "Trained-Reply", priority: 3 },
    { tag: "Sufficient-Words", priority: 2 },
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
      new_tag = Tag.find_or_create_by(name: tag_name)

      # find all tags with lower prioty and remove them
      lower_priority_tags =
        HeartSupport::RESOLUTION_HIERARCHY.select do |tag|
          tag[:priority] < priority
        end

      lower_priority_tag_names = lower_priority_tags.map { |tag| tag[:tag] }

      higher_priority_tags =
        HeartSupport::RESOLUTION_HIERARCHY.select do |tag|
          tag[:priority] > priority
        end

      higher_priority_tag_names = higher_priority_tags.map { |tag| tag[:tag] }

      # if there are lower priority tags on the topic, remove them and add the new tag
      if topic.tags.where(name: lower_priority_tag_names).present?
        lower_priority_tags.each do |tag|
          the_tag = Tag.find_or_create_by(name: tag[:tag])
          if topic.tags.include?(the_tag)
            topic.tags.delete(Tag.find_by(name: tag[:tag]))
          end
        end

        # # add the tag
        if topic.tags.exclude?(new_tag)
          topic.tags << new_tag
          topic.save
        end
      elsif topic.tags.where(name: higher_priority_tag_names).present?
        # do nothing
      else
        # # add the tag
        if topic.tags.exclude?(new_tag)
          topic.tags << new_tag
          topic.save
        end
      end
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
            # # remove staff escalation tag
            # HeartSupport.remove_topic_tags(ref_topic, "Staff-Escalation")
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

            # # add staff escalation tag
            # HeartSupport.add_topic_tags(ref_topic, "Staff-Escalation")

            # remove the asked user tag
            HeartSupport.remove_topic_tags(ref_topic, "Asked-User")

            # add resolution tag as user answered no
            HeartSupport.set_resolution_tag(ref_topic, "User-Answered-No")

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
      staff_escalation_tag = Tag.find_or_create_by(name: "Staff-Escalation")
      topic = post.topic
      user = post.user
      if STAFF_GROUPS.include?(user.primary_group_id) &&
           topic.tags.include?(staff_escalation_tag)
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
      supported_tag = Tag.find_or_create_by(name: "Supported")
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
        if supported
          if word_count > SUPPORT_LIMIT
            HeartSupport.set_resolution_tag(topic, "Sufficient-Words")
          end
        end
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
            HeartSupport.add_topic_tags(topic, "Supported")
            newly_supported = true
            supported = true
            topic.custom_fields["supported"] = true

            topic.save
          end

          # when word counts < 500
          if word_count < SUPPORT_LIMIT && !post.raw.blank?
            # if replier is a staff member or surge-replier, then add trained_replier tag
            if user.primary_group_id == 73 || user.primary_group_id == 42 ||
                 user.primary_group_id == 77
              # set the trained replier tag
              HeartSupport.set_resolution_tag(topic, "Trained-Reply")
              HeartSupport.add_topic_tags(topic, "Supported")
            end

            # if repler is a SWAT member and the second then set trained replier tag too
            if user.primary_group_id == 54 || user.primary_group_id == 76
              trained_repliers =
                topic
                  .posts
                  .joins(:user)
                  .where(users: { primary_group_id: [54, 76] })
                  .count
              if trained_repliers >= 2
                # set the trained replier tag
                HeartSupport.set_resolution_tag(topic, "Trained-Reply")
                HeartSupport.add_topic_tags(topic, "Supported")
              end
            end
          end

          # when the text contains a loom link, add a video reply tag, and sufficient words tag, supported
          # remove staff escalation tag if exists
          if post.raw.include?("https://www.loom.com/")
            # add video reply tag
            HeartSupport.add_topic_tags(topic, "Video-Reply")

            # add sufficient words tag
            HeartSupport.set_resolution_tag(topic, "Sufficient-Words")

            # add supported tag
            HeartSupport.add_topic_tags(topic, "Supported")

            # remove staff escalation tag
            HeartSupport.remove_topic_tags(topic, "Staff-Escalation")

            newly_supported = true
            supported = true
            topic.custom_fields["supported"] = true
            topic.save
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

    def self.check_sentiment(post)
      #  this method will send the post id to porter to check the sentiment
      #  if the sentiment is positive, we shall add a user answered yes tag
      post_id = post.id

      if Support::SUPPORT_CATEGORIES.include?(post.topic.category_id) &&
           post.post_number != 1
        url = "https://porter.heartsupport.com/api/sentiment?post_id=#{post_id}"
        uri = URI(url)
        # make a get request to the url
        response = Net::HTTP.get_response(uri)
        status = response.code
        body = response.body

        if (status == 200 || status == "200") && body.present?
          body = JSON.parse(body)
          score = body.fetch("score", nil)&.to_f

          if score
            if score > 0.25
              # resolve tags
              HeartSupport::Tags.resolve_tags(post.topic, "User-Answered-Yes")
            elsif score < -0.25
              HeartSupport::Tags.resolve_tags(post.topic, "User-Answered-No")
            end
          end
        end
      end
    end

    def self.send_discourse_webhook(
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

    def self.send_supplier_webhook(
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
      topic = Topic.find(topic_tag.topic_id)
      # when video reply tag is added
      video_reply_tag = Tag.find_or_create_by(name: "Video-Reply")
      user_selected_tag = Tag.find_or_create_by(name: "User-Selected")
      admin_selected_tag = Tag.find_or_create_by(name: "Admin-Selected")

      if topic_tag.tag_id == video_reply_tag.id ||
           topic_tag.tag_id == user_selected_tag.id ||
           topic_tag.tag_id == admin_selected_tag.id
        # remove the needs support tag
        HeartSupport.remove_topic_tags(topic, "Needs-Support")

        # add supported
        HeartSupport.add_topic_tags(topic, "Supported")
      end

      if topic_tag.tag_id == video_reply_tag.id
        # add the suffient words tag
        HeartSupport::Tags.resolve_tags(topic, "Sufficient-Words")
      end
      #
      #when user-selected tag is added
      # set the resolution tag as user selected
      if topic_tag.tag_id == user_selected_tag.id
        # resolve tags
        HeartSupport::Tags.resolve_tags(topic, "User-Selected")
      end

      #when admin selected tag is added
      if topic_tag.tag_id == admin_selected_tag.id
        # resolve tags
        HeartSupport::Tags.resolve_tags(topic, "Admin-Selected")
      end

      # send webhook for topic tag creation
      send_webhook(
        "created",
        topic_tag.topic_id,
        topic_tag.tag_id,
        topic_tag.tag.name,
        topic_tag.created_at,
        nil
      )
    end

    def self.delete_topic_tags(topic_tag)
      tag_id = topic_tag.tag_id
      tag = Tag.find(tag_id)

      if tag
        # send webhook for deleting
        send_webhook(
          "deleted",
          topic_tag.topic_id,
          tag.id,
          tag.name,
          topic_tag.created_at,
          Time.now
        )
      end
    end

    def self.send_webhook(
      event,
      topic_id,
      tag_id,
      tag_name,
      created_at,
      deleted_at
    )
      url = "https://porter.heartsupport.com/webhooks/topic_tags"
      uri = URI(url)

      res =
        Net::HTTP.post_form(
          uri,
          event: event,
          topic_id: topic_id,
          tag_id: tag_id,
          tag_name: tag_name,
          created_at: created_at,
          deleted_at: deleted_at
        )

      status = res.code
      Rails.logger.info(
        "topic tag webhook status: #{status} for #{tag_name} and #{event} , topic_id: #{topic_id}"
      )
    end

    def self.tag_platform_topic(topic)
      if PLATFORM_TOPICS_CATEGORIES.include?(topic.category_id)
        HeartSupport.add_topic_tags(topic, "Need-Listening-Ear")
      end
    end

    def self.resolve_tags(topic, tag_name)
      forum_tag =
        HeartSupport::RESOLUTION_HIERARCHY.find { |tag| tag[:tag] == tag_name }
      priority = forum_tag[:priority]
      lower_priority_tags =
        HeartSupport::RESOLUTION_HIERARCHY.select do |tag|
          tag[:priority] < priority
        end

      lower_priority_tags.each do |tag|
        the_tag = Tag.find_by(name: tag[:tag])
        if topic.tags.include?(the_tag)
          topic.tags.delete(Tag.find_by(name: tag[:tag]))
        end
        topic.save
      end

      # add the tag if the topic does not have higher priority tags
      higher_priority_tags =
        HeartSupport::RESOLUTION_HIERARCHY.select do |tag|
          tag[:priority] > priority
        end
      higher_priority_tag_names = higher_priority_tags.map { |tag| tag[:tag] }
      unless topic.tags.where(name: higher_priority_tag_names).present?
        new_tag = Tag.find_or_create_by(name: tag_name)
        if topic.tags.exclude?(new_tag)
          topic.tags << new_tag
          topic.save
        end
      end
    end
  end
end

# Notes
# Change priority to place sufficient words below trained reply
