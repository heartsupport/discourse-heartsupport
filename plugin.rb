# name: discourse-heartsupport
# about: A plugin that adds functionality to the heartsupport discourse forum. All plugins were combined and organised under one plugin.
# version: 1.1.0
# authors: Acacia Bengo Ssembajjwe
# url: https://github.com/heartsupport/discourse-heartsupport.git

# register_asset "javascripts/discourse/initializers/loom-record-button.js.es6"
# register_asset "stylesheets/custom.scss"

after_initialize do
  require_relative "lib/heart_support/support"
  require_relative "lib/heart_support/hs_ai"

  # on discourse status update to closed or invisible, remove the needs support tag
  DiscourseEvent.on(:topic_status_updated) do |topic, status, enabled|
    if status == "closed" && topic.closed
      HeartSupport.remove_topic_tags(topic, "Needs-Support")
    end

    if status == "visible" && !topic.visible
      HeartSupport.remove_topic_tags(topic, "Needs-Support")
    end
  end

  # on discourse topic_visible_status_updated, remove the needs support tag
  DiscourseEvent.on(:topic_visible_status_updated) do |topic, status, enabled|
    HeartSupport.remove_topic_tags(topic, "Needs-Support") if visible == false
  end

  # after topic tag is created, check if it's a video reply tag
  ::TopicTag.class_eval do
    after_create { HeartSupport::Tags.process_tags(self) }
  end

  # after deleting a topic tag, send webhook
  ::TopicTag.class_eval do
    after_destroy { HeartSupport::Tags.delete_topic_tags(self) }
  end

  # # after topic is created, add listening tag if platform topic
  # ::Topic.class_eval do
  #   after_create { HeartSupport::Tags.tag_platform_topic(self) }
  # end

  ::Post.class_eval do
    after_create do
      HeartSupport::Support.process_post(self)
      HeartSupport::Support.check_response(self)
      HeartSupport::Support.update_tags(self)
      HeartSupport::Support.check_sentiment(self)
    end
  end

  # add RemoveSupportTagJob
  class ::Jobs::RemoveSupportTagJob < Jobs::Scheduled
    SUPPORT_LIMIT = 500
    ASK_USER_LIMIT = 300
    SUPPORT_CATEGORIES = [67, 77, 85, 87, 88, 89, 102, 106]

    every 1.day

    def execute(args)
      supported_tag = Tag.find_or_create_by(name: "Supported")
      video_reply_tag = Tag.find_or_create_by(name: "Video-Reply")

      # change the query for topics to be escalated based on create date instead of last_posted_at 20/02/24
      #
      reference_date = (14.days.ago.beginning_of_day..14.days.ago.end_of_day)
      topics =
        Topic
          .where(created_at: reference_date)
          .where("topics.archetype = ?", "regular")
          .where.not(
            id: TopicTag.select(:topic_id).where(tag_id: supported_tag.id)
          )
          .where.not(closed: true)
          .where(deleted_at: nil)
          .where(category_id: SUPPORT_CATEGORIES)

      topics.each do |topic|
        HeartSupport.remove_topic_tags(topic, "Needs-Support")
        HeartSupport.remove_topic_tags(topic, "Asked-User")

        word_count =
          topic.posts.where.not(user_id: topic.user_id).sum(:word_count)

        # add the supported tag
        if word_count >= SUPPORT_LIMIT
          # add supported tag
          HeartSupport.add_topic_tags(topic, "Supported")
          # add sufficient words tag
          HeartSupport.set_resolution_tag(topic, "Sufficient-Words")
          topic.custom_fields["supported"] = true
        elsif topic.tags.include?(video_reply_tag)
          topic.custom_fields["supported"] = true
          HeartSupport.set_resolution_tag(topic, "Sufficient-Words")
          # add supported tag
          HeartSupport.add_topic_tags(topic, "Supported")
        else
          puts "topic #{topic.id} does not have enough words"
          if SUPPORT_CATEGORIES.include?(topic.category_id) && topic.visible &&
               !topic.closed
            puts "topic #{topic.id} is being escalated"
            #  add insuffficient words tag
            HeartSupport.set_resolution_tag(topic, "Insufficient")
            # remove the ask user tag
            HeartSupport.remove_topic_tags(topic, "Asked-User")

            # send similar conversation message
            puts "sending similar conversation message"
            HsAi.share_similar_experience(topic)
          end
        end

        topic.save

        push_topic_to_supplier(topic)
      end
    end

    def push_topic_to_supplier(topic)
      # make an API call to create a supplier topic
      Net::HTTP.post_form(
        URI("https://porter.heartsupport.com/webhooks/supplier"),
        topic_id: topic.id,
        supported: true,
        username: topic.user.username,
        category_id: topic.category_id,
        closed: topic.closed
      )
    end
  end

  # add FollowUpSupportJob
  class ::Jobs::FollowUpSupportJob < Jobs::Scheduled
    ASK_CATEGORIES = [67, 89, 4]
    ASK_USER_LIMIT = 300

    every 6.hours

    def execute(args)
      supported_tag = Tag.find_or_create_by(name: "Supported")
      asked_user_tag = Tag.find_or_create_by(name: "Asked-User")
      # venting_no_reply_needed_tag = Tag.find_or_create_by(name: "Venting-No-Reply-Needed")
      video_reply_tag = Tag.find_or_create_by(name: "Video-Reply")

      # query all all topics created > 24 hours, does not have a supported tag, and don't have an asked user tag

      topics =
        Topic
          .where(created_at: 14.days.ago..24.hours.ago)
          .where("topics.archetype = ?", "regular")
          .where("topics.posts_count > ?", 1)
          .where(category_id: ASK_CATEGORIES)
          .where.not(
            id:
              TopicTag.select(:topic_id).where(
                tag_id: [supported_tag.id, asked_user_tag.id]
              )
          )
          .where.not(
            id: TopicCustomField.select(:topic_id).where(name: "asked_user")
          )
          .distinct

      topics.each do |topic|
        next if topic.custom_fields["asked_user"].present?
        word_count =
          topic.posts.where.not(user_id: topic.user_id).sum(:word_count)
        if word_count >= ASK_USER_LIMIT
          # send a message to the user asking if they feel supported
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

      video_topics =
        Topic
          .where("topics.archetype = ?", "regular")
          .where(category_id: ASK_CATEGORIES)
          .where.not(
            id: TopicCustomField.select(:topic_id).where(name: "asked_user")
          )
          .where(category_id: ASK_CATEGORIES)
          .where(
            id: TopicTag.select(:topic_id).where(tag_id: video_reply_tag.id)
          )
          .distinct

      video_topics.each do |topic|
        next if topic.custom_fields["asked_user"].present?
        require_dependency "post_creator"
        system_user = User.find_by(username: "system")

        dm_params = {
          title: "Follow Up on Your Recent Post",
          raw:
            "Hi #{topic.user.username}, On this topic you posted, did you get the support you needed? \n " \
              "#{topic.url} \n" \
              "Reply to this message with YES if you feel supported, or NO if you don't.",
          archetype: Archetype.private_message,
          target_usernames: [topic.user.username],
          custom_fields: {
            ref_topic_id: topic.id
          }
        }
        PostCreator.create!(system_user, dm_params)
        HeartSupport.add_topic_tags(topic, "Asked-User")
        topic.custom_fields["asked_user"] = "true"

        topic.save
      end
    end
  end

  # add a job to update user badges
  class ::Jobs::UpdateUserBadges < Jobs::Scheduled
    BADGE_THRESHOLDS = [
      { id: 211, threshold: 1 },
      { id: 213, threshold: 25 },
      { id: 212, threshold: 10 },
      { id: 214, threshold: 50 },
      { id: 215, threshold: 75 },
      { id: 216, threshold: 100 },
      { id: 218, threshold: 150 },
      { id: 219, threshold: 200 },
      { id: 220, threshold: 300 },
      { id: 221, threshold: 500 },
      { id: 222, threshold: 1000 }
    ]

    every 1.day

    def execute(args)
      # find all users in support groups and active in the last 25 hours
      sql =
        "
          WITH swat_users AS (
            SELECT DISTINCT
                user_id
            FROM
                group_users
            WHERE
                group_id IN (54, 73, 76)
          )
          SELECT
              users.id,
              users.username,
              COUNT(DISTINCT posts.id) as reply_count

          FROM
              users
              INNER JOIN swat_users ON users.id = swat_users.user_id
              LEFT JOIN posts ON posts.user_id = users.id AND posts.post_number != 1
              LEFT JOIN user_badges ON user_badges.user_id = users.id
              JOIN topics on topics.id = posts.topic_id
          WHERE
              users.last_posted_at >= (CURRENT_DATE - INTERVAL '30 Days' ) AND
              topics.category_id IN (67,77,78,85,86,87,102,106,89)
          GROUP BY
              users.id,
              users.username
          ORDER BY
              reply_count DESC
        "

      users = ActiveRecord::Base.connection.execute(sql)

      users.each do |user|
        user_id = user["id"]
        reply_count = user["reply_count"].to_i

        filtered_badges =
          BADGE_THRESHOLDS.select { |badge| reply_count >= badge[:threshold] }

        if filtered_badges.present?
          filtered_badges.each do |badge|
            unless UserBadge.exists?(user_id: user_id, badge_id: badge[:id])
              badge =
                UserBadge.new(
                  user_id: user_id,
                  badge_id: badge[:id],
                  granted_at: Time.now,
                  granted_by_id: -1
                )
              if badge.save
                puts "Badge #{badge[:id]} added to user #{user_id}, #{user["username"]}"
              else
                puts "Error adding badge #{badge[:id]} to user #{user_id}, #{user["username"]}"
                puts "reason: #{badge.errors.full_messages}"
              end
            end
          end
        end
      end
    end
  end
end
