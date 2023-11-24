# name: discourse-heartsupport
# about: A plugin that adds functionality to the heartsupport discourse forum. All plugins were combined and organised under one plugin.
# version: 1.1.0
# authors: Acacia Bengo Ssembajjwe
# url: https://github.com/heartsupport/discourse-heartsupport.git

after_initialize do
  require_relative "lib/heart_support/support"

  # on discourse status update to closed or invisible, remove the needs support tag
  DiscourseEvent.on(:topic_status_updated) do |topic, status, enabled|
    needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")

    if topic.tags.include?(needs_support_tag)
      if status == "closed" && topic.closed
        topic.tags.delete needs_support_tag
      end

      if status == "visible" && !topic.visible
        topic.tags.delete needs_support_tag
      end
    end
  end

  ::Post.class_eval do
    after_create do
      HeartSupport::Support.check_support(self)
      HeartSupport::Support.check_response(self)
    end
  end

  # add RemoveSupportTagJob
  class ::Jobs::RemoveSupportTagJob < Jobs::Scheduled
    SUPPORT_LIMIT = 500
    ASK_USER_LIMIT = 300

    every 1.day

    def execute(args)
      needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")
      supported_tag = Tag.find_or_create_by(name: "Supported")
      asked_user_tag = Tag.find_or_create_by(name: "Asked-User")
      staff_escalation_tag = Tag.find_or_create_by(name: "Staff-Escalation")
      sufficient_words_tag = Tag.find_or_create_by(name: "Sufficient-Words")
      video_reply_tag = Tag.find_or_create_by(name: "Video-Reply")

      # find all topics whose last activity was on this day 14 days ago with the regular archetype and not the supported tag
      # count the non-op posts word count
      # if the word count is >= 500, add the supported tag & sufficient words tag else add the staff escalation tag

      topics = Topic
        .where("topics.last_posted_at BETWEEN ? AND ?", 14.days.ago.beginning_of_day, 14.days.ago.end_of_day)
        .where("topics.archetype = ?", "regular")
        .where.not(id: TopicTag.select(:topic_id).where(tag_id: supported_tag.id))
        .where.not(closed: true)
        .where(deleted_at: nil)

      topics.each do |topic|
        topic.tags.delete needs_support_tag
        topic.tags.delete asked_user_tag

        word_count = topic.posts.where.not(user_id: topic.user_id).sum(:word_count)

        # add the supported tag
        if word_count >= SUPPORT_LIMIT
          topic.tags << supported_tag unless topic.tags.include?(supported_tag)
          topic.custom_fields["supported"] = true
          topic.tags << sufficient_words_tag unless topic.tags.include?(sufficient_words_tag)
        elsif topic.tags.include?(video_reply_tag)
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

  # add FollowUpSupportJob
  class ::Jobs::FollowUpSupportJob < Jobs::Scheduled
    ASK_CATEGORIES = [67, 89]
    ASK_USER_LIMIT = 300

    every 6.hours

    def execute(args)
      supported_tag = Tag.find_or_create_by(name: "Supported")
      asked_user_tag = Tag.find_or_create_by(name: "Asked-User")
      venting_no_reply_needed_tag = Tag.find_or_create_by(name: "Venting-No-Reply-Needed")
      video_reply_tag = Tag.find_or_create_by(name: "Video-Reply")

      # query all all topics created > 24 hours, does not have a supported tag, and don't have an asked user tag

      topics = Topic
        .where("topics.created_at BETWEEN ? AND ?", 14.days.ago, 24.hours.ago)
        .where("topics.archetype = ?", "regular")
        .where("topics.posts_count > ?", 1)
        .where(category_id: ASK_CATEGORIES)
        .where.not(id: TopicTag.select(:topic_id).where(tag_id: [supported_tag.id, venting_no_reply_needed_tag.id, asked_user_tag.id]))
        .where.not(id: TopicCustomField.select(:topic_id).where(name: "asked_user"))
        .distinct

      topics.each do |topic|
        next if topic.custom_fields["asked_user"].present?
        word_count = topic.posts.where.not(user_id: topic.user_id).sum(:word_count)
        if word_count >= ASK_USER_LIMIT
          # send a message to the user asking if they feel supported
          require_dependency "post_creator"
          system_user = User.find_by(username: "system")

          dm_params = {
            title: "Follow Up on Your Recent Post",
            raw: "Hi #{topic.user.username}, On this topic you posted, did you get the support you needed? \n " \
            "#{topic.url} \n" \
            "Reply to this message with YES if you feel supported, or NO if you don't.",
            archetype: Archetype.private_message,
            target_usernames: [topic.user.username],
            custom_fields: { ref_topic_id: topic.id },
          }
          PostCreator.create!(system_user, dm_params)
          topic.custom_fields["asked_user"] = "true"
          topic.tags << asked_user_tag unless topic.tags.include?(asked_user_tag)
          topic.save!
        end
      end

      video_topics = Topic
        .where("topics.archetype = ?", "regular")
        .where(category_id: ASK_CATEGORIES)
        .where.not(id: TopicCustomField.select(:topic_id).where(name: "asked_user"))
        .where(category_id: ASK_CATEGORIES)
        .where(id: TopicTag.select(:topic_id).where(tag_id: video_reply_tag.id))
        .distinct

      video_topics.each do |topic|
        next if topic.custom_fields["asked_user"].present?
        require_dependency "post_creator"
        system_user = User.find_by(username: "system")

        dm_params = {
          title: "Follow Up on Your Recent Post",
          raw: "Hi #{topic.user.username}, On this topic you posted, did you get the support you needed? \n " \
          "#{topic.url} \n" \
          "Reply to this message with YES if you feel supported, or NO if you don't.",
          archetype: Archetype.private_message,
          target_usernames: [topic.user.username],
          custom_fields: { ref_topic_id: topic.id },
        }
        PostCreator.create!(system_user, dm_params)
        topic.custom_fields["asked_user"] = "true"
        topic.tags << asked_user_tag unless topic.tags.include?(asked_user_tag)
        topic.save!
      end
    end
  end
end
