# name: discourse-heartsupport
# about: A plugin that adds functionality to the heartsupport discourse forum. All plugins were combined and organised under one plugin.
# version: 1.1.0
# authors: Acacia Bengo Ssembajjwe
# url: https://github.com/heartsupport/discourse-heartsupport.git

after_initialize do
  require_relative "lib/heart_support/support"

  # add job that runs everyday to ask users if they feel supported
  require_relative "lib/heart_support/jobs/follow_up_support_job"

  # add a job that runs everyday to remove the needs support tag from topics that are older than 14 days
  require_relative "lib/heart_support/jobs/remove_support_tag_job"

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
end
