# name: discourse-supported
# about: Mark topics as supported when they've reached a certain threshold
# version: 0.1.2
# authors: Thomas Hart II
# url: https://github.com/myrridin/discourse-supported

after_initialize do
  class ::Post
    after_create :check_for_support

    def check_for_support
      needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")
      supported_tag = Tag.find_or_create_by(name: "Supported")
      supplier_url = URI("https://porter.heartsupport.com/webhooks/supplier")

      if is_first_post?
        # If it's the first post, add the needs support tag
        topic.tags << needs_support_tag
        # make an API call to create a supplier topic
        res = Net::HTTP.post_form(supplier_url, topic_id: topic_id, supported: false, username: user.username)
      else
        supported = !topic.tags.include?(needs_support_tag)
        newly_supported = false

        unless supported
          # If it's not the first post and it has a needs support tag, check the support threshold and modify tags as necessary

          replies = topic.posts.where("post_number > 1")
          reply_word_count = replies.sum(:word_count)

          if (replies.length >= 1 && reply_word_count >= 500)
            topic.tags.delete needs_support_tag
            # topic.tags << supported_tag
            supported = true
            newly_supported = true

            # make an API call to mark supplier topic as supported
            res = Net::HTTP.post_form(supplier_url, topic_id: topic_id, supported: true, username: user.username)
          end
        end

        Rails.logger.info("POSTING TO HSAPPS")
        uri = URI("https://porter.heartsupport.com/twilio/discourse_webhook")
        res = Net::HTTP.post_form(uri, topic_id: topic_id, supported: supported, newly_supported: newly_supported, body: cooked, username: user.username)
      end

      Rails.logger.info("CHECKING FOR SUPPORT ON #{self}")
    end
  end
end
