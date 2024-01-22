module HeartSupport
  module Jobs
    class ::Jobs::FollowUpSupportJob < ::Jobs::Scheduled
      ASK_CATEGORIES = [67, 89, 4]
      ASK_USER_LIMIT = 300

      every 1.day

      def execute(args)
        supported_tag = Tag.find_or_create_by(name: "Supported")
        asked_user_tag = Tag.find_or_create_by(name: "Asked-User")
        # venting_no_reply_needed_tag = Tag.find_or_create_by(name: "Venting-No-Reply-Needed")

        # query all all topics created > 24 hours, does not have a supported tag, and don't have an asked user tag
        topics =
          Topic
            .where(
              "topics.created_at < ? AND topics.created_at > ?",
              24.hours.ago,
              14.days.ago
            )
            .where("topics.archetype = ?", "regular")
            .where("topics.posts_count > ?", 1)
            .where("topics.word_count >= ?", ASK_USER_LIMIT)
            .where("topics.category_id IN (?)", ASK_CATEGORIES)
            .joins("INNER JOIN topic_tags ON topic_tags.topic_id = topics.id")
            .where("topic_tags.tag_id != ?", supported_tag.id)
            .joins(
              "INNER JOIN topic_custom_fields ON topic_custom_fields.topic_id = topics.id"
            )
            .where("topic_custom_fields.name = ?", "asked_user")

        topics.each do |topic|
          next if topic.custom_fields["asked_user"].present?
          next if topic.tags.include?(asked_user_tag)
          next if topic.tags.include?(supported_tag)
          # send a message to the user asking if they feel supported
          require_dependency "post_creator"
          system_user = User.find_by(username: "system")

          dm_params = {
            title: "Follow Up on Your Recent Post",
            raw:
              "Hi #{topic.user.username}, On this topic you posted, did you get the advice " \
                "you needed? \n #{topic.url} \n" \
                "Reply to this message with YES if you feel supported, or NO if you don't.",
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
  end
end
