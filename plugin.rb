# name: discourse-supported
# about: Mark topics as supported when they've reached a certain threshold
# version: 0.1.2
# authors: Thomas Hart II, Acacia Bengo Ssembajjwe
# url: https://github.com/myrridin/discourse-supported

after_initialize do
  class ::Post
    after_create :check_for_support

    def check_for_support
      needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")
      supported_tag = Tag.find_or_create_by(name: "Supported")
      supplier_url = URI("https://porter.heartsupport.com/webhooks/supplier")

      supported_categories = [67, 77, 85, 87, 88, 89]
      return unless supported_categories.include?(topic.category_id)

      if is_first_post?
        # If it's the first post, add the needs support tag
        topic.tags << needs_support_tag
        supported = false
      else
        supported = !topic.tags.include?(needs_support_tag)
        newly_supported = false

        #if supported is false then check if meets requirmenets to change it true
        if supported == false
          replies = topic.posts.where("post_number > 1")
          reply_word_count = replies.sum(:word_count)

          if replies.length >= 1 && reply_word_count >= 500
            topic.tags.delete needs_support_tag
            # topic.tags << supported_tag
            supported = true
            newly_supported = true
          end
        end

        Rails.logger.info("POSTING TO HSAPPS")
        uri = URI("https://porter.heartsupport.com/twilio/discourse_webhook")
        res = Net::HTTP.post_form(uri, topic_id: topic_id, supported: supported, newly_supported: newly_supported, body: cooked, username: user.username)
      end

      Rails.logger.info("CHECKING FOR SUPPORT ON #{self}")

      # send webhook request to supplier
      Rails.logger.info("POSTING TO SUPPLIER")
      # make an API call to create a supplier topic
      res = Net::HTTP.post_form(
        supplier_url,
        topic_id: topic_id,
        supported: supported,
        username: user.username,
        category_id: topic.category_id,
        closed: topic.closed,
      )
    end
  end
end
