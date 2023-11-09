module HeartSupport
  module Jobs
    class ::Jobs::RemoveSupportTagJob < ::Jobs::Scheduled
      SUPPORT_LIMIT = 500
      ASK_USER_LIMIT = 300

      every 1.day

      def execute(args)
        needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")
        supported_tag = Tag.find_or_create_by(name: "Supported")
        asked_user_tag = Tag.find_or_create_by(name: "Asked-User")
        staff_escalation_tag = Tag.find_or_create_by(name: "Staff-Escalation")
        sufficient_words_tag = Tag.find_or_create_by(name: "Sufficient-Words")

        # Query for all with last post created > 14 days && do not not have a "Supported tag"
        topics = Topic
          .where("last_posted_at < ?", 14.days.ago)
          .where("topics.archetype = ?", "regular")
          .left_outer_joins(:topic_tags)
          .where("topic_tags.tag_id != ?", supported_tag.id)

        topics.each do |topic|
          topic.tags.delete needs_support_tag
          topic.tags.delete asked_user_tag

          # add the supported tag
          if topic.posts.sum(:word_count) >= SUPPORT_LIMIT
            topic.tags << supported_tag unless topic.tags.include?(supported_tag)
            topic.custom_fields["supported"] = true
            topic.tags << sufficient_words_tag unless topic.tags.include?(sufficient_words_tag)
          else
            topic.tags << staff_escalation_tag unless topic.tags.include?(staff_escalation_tag)
          end

          topic.save!

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
          closed: topic.closed,
        )
      end
    end
  end
end
