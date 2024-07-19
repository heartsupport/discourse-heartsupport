require "rails_helper"
require "rspec/mocks"

RSpec.describe HeartSupport::Support, type: :model do
  describe "#set_resolution_tag" do
    let!(:user) { Fabricate(:active_user) }
    let!(:topic) do
      Fabricate(:topic, category_id: 67, archetype: "regular", user: user)
    end

    let!(:trained_reply_tag) { Tag.find_or_create_by(name: "Trained-Reply") }
    let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
    let!(:admin_selected_tag) { Tag.find_or_create_by(name: "Admin-Selected") }

    # before { allow(HeartSupport).to receive(:set_resolution_tag) }

    context "when tag is low in priority" do
      before do
        topic.tags << trained_reply_tag
        topic.save!
        topic.reload
        puts "topic_tags: #{topic.reload.tags.inspect}"
      end

      it "does not add the needs support tag" do
        puts "trained_reply_tag: #{trained_reply_tag.inspect}"
        puts "topic: #{topic.inspect}"
        puts "tags: #{topic.tags.inspect}"
        expect(topic.reload.tags.include?(trained_reply_tag)).to eq(true)
        expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
        HeartSupport.set_resolution_tag(topic, "Needs-Support")
        expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
      end
    end

    context "when tag is high in priority" do
      before do
        topic.tags << trained_reply_tag
        topic.save!
        puts "topic_tags: #{topic.reload.tags.inspect}"
      end

      it "removes the trained reply tag and adds the admin selected tag" do
        puts "topic: #{topic.inspect}"
        puts "tags: #{topic.tags.inspect}"
        expect(topic.tags.include?(trained_reply_tag)).to eq(true)
        HeartSupport.set_resolution_tag(topic, "Admin-Selected")
        expect(topic.reload.tags.include?(trained_reply_tag)).to eq(false)
        expect(topic.reload.tags.include?(admin_selected_tag)).to eq(true)
      end
    end
  end

  # context "Post Creation" do
  #   let(:stub_supplier) do
  #     stub_request(
  #       :post,
  #       %r{https://porter.heartsupport.com/webhooks/supplier}
  #     ).to_return(status: 200, body: "", headers: {})
  #   end
  #   let(:stub_hsapps) do
  #     stub_request(
  #       :post,
  #       %r{https://porter.heartsupport.com/twilio/discourse_webhook}
  #     ).to_return(status: 200, body: "", headers: {})
  #   end

  #   context "when the post is the first post" do
  #     let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
  #     let(:user) { Fabricate(:active_user) }
  #     let(:topic) do
  #       Fabricate(:topic, category_id: 67, archetype: "regular", user: user)
  #     end

  #     before do
  #       stub_supplier
  #       stub_hsapps
  #     end
  #     it "adds the needs support tag" do
  #       Fabricate(:post, topic: topic)
  #       expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
  #       expect(stub_supplier).to have_been_requested.once
  #       expect(stub_hsapps).to_not have_been_requested
  #     end
  #   end

  #   context "when the post is not the first post" do
  #     let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
  #     let(:user) { Fabricate(:walter_white) }
  #     let(:topic) { Fabricate(:topic, category_id: 67, archetype: "regular") }
  #     let(:post) { Fabricate(:post, topic: topic) }
  #     let(:non_op_user) { Fabricate(:user) }

  #     before do
  #       stub_supplier
  #       stub_hsapps
  #     end

  #     it "does not add the needs support tag" do
  #       topic =
  #         Fabricate(:topic, category_id: 67, archetype: "regular", user: user)
  #       first_post =
  #         Post.create!(
  #           user_id: user.id,
  #           raw: ("Hello ") * 30,
  #           topic_id: topic.id
  #         )

  #       Post.create!(
  #         user_id: non_op_user.id,
  #         raw: ("Hello ") * 30,
  #         topic_id: topic.id
  #       )

  #       expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
  #       expect(first_post.is_first_post?).to eq(true)
  #       expect(stub_supplier).to have_been_requested.times(2)
  #       expect(stub_hsapps).to have_been_requested.times(1)
  #     end

  #     it "removes the needs support tag > 500 words from Non-OP users" do
  #       topic =
  #         Fabricate(:topic, category_id: 67, archetype: "regular", user: user)

  #       Post.create!(
  #         user_id: user.id,
  #         raw: ("Hello ") * 300,
  #         topic_id: topic.id
  #       )
  #       Post.create!(
  #         user_id: non_op_user.id,
  #         raw: ("Hello ") * 300,
  #         topic_id: topic.id
  #       )
  #       Post.create!(
  #         user_id: non_op_user.id,
  #         raw: ("Hello ") * 300,
  #         topic_id: topic.id
  #       )
  #       expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
  #     end

  #     it "does not remove the needs support tag < 500 words from Non-OP users" do
  #       topic =
  #         Fabricate(:topic, category_id: 67, archetype: "regular", user: user)
  #       Post.create!(
  #         user_id: user.id,
  #         raw: ("Hello ") * 300,
  #         topic_id: topic.id
  #       )
  #       Post.create!(
  #         user_id: user.id,
  #         raw: ("Hello ") * 300,
  #         topic_id: topic.id
  #       )
  #       Post.create!(
  #         user_id: non_op_user.id,
  #         raw: ("Hello ") * 300,
  #         topic_id: topic.id
  #       )

  #       expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
  #     end
  #   end

  #   context "when the post is a staff replier to an escalated topic" do
  #     let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
  #     let!(:staff_escalation_tag) do
  #       Tag.find_or_create_by(name: "Staff-Escalation")
  #     end
  #     let!(:staff_replied_tag) { Tag.find_or_create_by(name: "Staff-Replied") }
  #     let!(:asked_user_tag) { Tag.find_or_create_by(name: "Asked-User") }
  #     let(:user) { Fabricate(:active_user) }
  #     let(:topic) do
  #       Fabricate(:topic, category_id: 67, archetype: "regular", user: user)
  #     end
  #     let(:group) { Fabricate(:group, id: 42) }

  #     before do
  #       stub_supplier
  #       stub_hsapps
  #     end

  #     it "adds the staff replied tag" do
  #       user.update!(primary_group_id: group.id)
  #       Fabricate(:post, topic: topic)
  #       topic.tags << staff_escalation_tag
  #       topic.save!

  #       staff_post = Fabricate(:post, topic: topic, user: user)
  #       expect(topic.reload.tags.include?(staff_replied_tag)).to eq(true)
  #     end
  #   end
  # end

  # context "Private Messages" do
  #   let(:topic) { Fabricate(:topic, archetype: "regular") }
  #   let(:system_user) { User.find_by(username: "system") }
  #   let(:user) { Fabricate(:evil_trout) }
  #   let(:private_message) do
  #     post =
  #       PostCreator.create(
  #         system_user,
  #         {
  #           title: "Follow Up on Your Recent Post",
  #           archetype: Archetype.private_message,
  #           target_usernames: [user.username],
  #           raw: Faker::Lorem.paragraph(sentence_count: 2),
  #           custom_fields: {
  #             ref_topic_id: topic.id
  #           }
  #         }
  #       )

  #     Rails.logger.error(post.errors.full_messages) if post.errors.present?
  #   end
  #   let(:pm_topic_id) { private_message.topic_id }
  #   let(:pm_topic) { Topic.find_by(id: pm_topic_id) }
  #   let(:stub_supplier) do
  #     stub_request(
  #       :post,
  #       %r{https://porter.heartsupport.com/webhooks/supplier}
  #     ).to_return(status: 200, body: "", headers: {})
  #   end
  #   let(:stub_hsapps) do
  #     stub_request(
  #       :post,
  #       %r{https://porter.heartsupport.com/twilio/discourse_webhook}
  #     ).to_return(status: 200, body: "", headers: {})
  #   end
  #   let(:stub) do
  #     stub_request(
  #       :post,
  #       %r{https://porter.heartsupport.com/webhooks/followup}
  #     ).to_return(status: 200, body: "", headers: {})
  #   end

  #   before do
  #     stub_supplier
  #     stub_hsapps
  #     stub
  #   end
  #   context "when message from user" do
  #     context "when the user responds yes" do
  #       let(:response) do
  #         "Thank you for your feedback! \n" \
  #           "Click on the form and answer the one question because it will help us know specifically what helped: " \
  #           "<a href='https://docs.google.com/forms/d/e/1FAIpQLScrXmJ96G3l4aypDtf307JycIhFHS9_8WMkF65m9JiM9Xm6WA/viewform' target='_blank'>
  #         https://docs.google.com/forms/d/e/1FAIpQLScrXmJ96G3l4aypDtf307JycIhFHS9_8WMkF65m9JiM9Xm6WA/viewform
  #         </a> \n"
  #       end
  #       it "responds with multiple choice" do
  #         expect {
  #           Post.create!(topic_id: pm_topic_id, user_id: user.id, raw: "Yes")
  #         }.to change { pm_topic.posts.count }.by(2)
  #         expect(stub).to_not have_been_requested
  #         expect(pm_topic.posts.last.raw).to include(response)
  #       end
  #     end
  #     context "when the user responds no" do
  #       let(:response) do
  #         "Thank you for sharing that with us. We'll get you more support. \n" \
  #           "Click on the form and answer the one question because it will help us know how we can improve: " \
  #           "<a href='https://docs.google.com/forms/d/e/1FAIpQLSdxWbRMQPUe0IxL0xBEDA5RZ5B0a9Yl2e25ltW5RGDE6J2DOA/viewform' target='_blank'>https://docs.google.com/forms/d/e/1FAIpQLSdxWbRMQPUe0IxL0xBEDA5RZ5B0a9Yl2e25ltW5RGDE6J2DOA/viewform</a>"
  #       end
  #       it "responds with multiple choice" do
  #         expect {
  #           Post.create!(topic_id: pm_topic_id, user_id: user.id, raw: "No")
  #         }.to change { pm_topic.posts.count }.by(2)
  #         expect(stub).to_not have_been_requested
  #         expect(pm_topic.posts.last.raw).to include(response)
  #         expect(topic.custom_fields["staff_escalation"]).to eq("t")
  #       end
  #     end
  #     context "when the user responds with neither yes or no" do
  #       it "send webhook request" do
  #         # find send a no response
  #         Post.create!(topic_id: pm_topic_id, user_id: user.id, raw: "No")

  #         # send follow up message
  #         expect {
  #           Post.create!(
  #             topic_id: pm_topic_id,
  #             user_id: user.id,
  #             raw: "This is a test random message"
  #           )
  #         }.to change { pm_topic.posts.count }.by(1)
  #         expect(stub).to have_been_requested.once
  #       end
  #     end
  #   end
  #   context "when message from system" do
  #     let(:user) { User.find_by(username: "system") }

  #     it "does not get processed and receive a reply" do
  #       expect {
  #         Post.create(
  #           topic_id: pm_topic_id,
  #           user_id: user.id,
  #           raw: "This is a test random message"
  #         )
  #       }.to change { pm_topic.posts.count }.by(1)
  #       expect(stub).to_not have_been_requested.once
  #     end
  #   end
  # end

  # context "Remove tags when topic status changes" do
  #   before do
  #     stub_supplier
  #     stub_hsapps
  #   end

  #   let(:stub_supplier) do
  #     stub_request(
  #       :post,
  #       %r{https://porter.heartsupport.com/webhooks/supplier}
  #     ).to_return(status: 200, body: "", headers: {})
  #   end
  #   let(:stub_hsapps) do
  #     stub_request(
  #       :post,
  #       %r{https://porter.heartsupport.com/twilio/discourse_webhook}
  #     ).to_return(status: 200, body: "", headers: {})
  #   end
  #   let(:user) { Fabricate(:newuser) }
  #   let(:topic) do
  #     Fabricate(:topic, category_id: 67, archetype: "regular", user: user)
  #   end
  #   let!(:post) { Fabricate(:post, topic: topic, user: user) }
  #   let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }

  #   context "when topic is closed" do
  #     before do
  #       stub_supplier
  #       stub_hsapps
  #     end

  #     it "removes the needs support tag" do
  #       expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
  #       topic.update!(closed: true)
  #       # send discouse event
  #       DiscourseEvent.trigger(:topic_status_updated, topic, "closed", "closed")
  #       expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
  #     end
  #   end

  #   context "when topic is archived" do
  #     before do
  #       stub_supplier
  #       stub_hsapps
  #     end

  #     it "removes the needs support tag" do
  #       expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
  #       topic.update!(visible: false)
  #       DiscourseEvent.trigger(
  #         :topic_status_updated,
  #         topic,
  #         "visible",
  #         "visible"
  #       )
  #       expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
  #     end
  #   end
  # end

  # context "Background Jobs" do
  #   let(:stub_supplier) do
  #     stub_request(
  #       :post,
  #       %r{https://porter.heartsupport.com/webhooks/supplier}
  #     ).to_return(status: 200, body: "", headers: {})
  #   end
  #   let(:stub_hsapps) do
  #     stub_request(
  #       :post,
  #       %r{https://porter.heartsupport.com/twilio/discourse_webhook}
  #     ).to_return(status: 200, body: "", headers: {})
  #   end

  #   before do
  #     stub_supplier
  #     stub_hsapps
  #   end

  #   context "Clean up topics after 14 days" do
  #     let(:topic_1) do
  #       Fabricate(
  #         :topic,
  #         created_at: 14.days.ago.beginning_of_day,
  #         archetype: "regular"
  #       )
  #     end
  #     let(:topic_2) do
  #       Fabricate(
  #         :topic,
  #         created_at: 14.days.ago,
  #         archetype: "regular",
  #         category_id: 106,
  #         created_at: 14.days.ago
  #       )
  #     end
  #     let(:topic_3) do
  #       Fabricate(
  #         :topic,
  #         created_at: 14.days.ago,
  #         archetype: "regular",
  #         category_id: 106
  #       )
  #     end
  #     let(:supported_tag) { Tag.find_or_create_by(name: "Supported") }
  #     let(:staff_escalation_tag) do
  #       Tag.find_or_create_by(name: "Staff-Escalation")
  #     end
  #     let(:video_reply_tag) { Tag.find_or_create_by(name: "Video-Reply") }
  #     let(:sufficient_words_tag) do
  #       Tag.find_or_create_by(name: "Sufficient-Words")
  #     end

  #     describe "#execute" do
  #       it "assigns the closing tags correctly" do
  #         # create posts with certain word length
  #         Fabricate(:post, topic: topic_1, user: Fabricate(:user))
  #         Fabricate(:post, topic: topic_1, user: Fabricate(:user))
  #         Fabricate(
  #           :post,
  #           topic: topic_2,
  #           user: Fabricate(:user),
  #           raw: ("Hello ") * 200
  #         )
  #         Fabricate(
  #           :post,
  #           topic: topic_2,
  #           user: Fabricate(:user),
  #           raw: ("Hello ") * 200
  #         )
  #         Fabricate(
  #           :post,
  #           topic: topic_3,
  #           user: Fabricate(:user),
  #           raw: ("Hello ") * 300
  #         )
  #         Fabricate(
  #           :post,
  #           topic: topic_3,
  #           user: Fabricate(:user),
  #           raw: ("Hello ") * 300
  #         )
  #         topic_1.tags << video_reply_tag

  #         ::Jobs::RemoveSupportTagJob.new.execute({})

  #         expect(topic_1.reload.tags.include?(sufficient_words_tag)).to eq(true)
  #         expect(topic_1.reload.tags.include?(video_reply_tag)).to eq(true)
  #         expect(topic_2.reload.tags.include?(staff_escalation_tag)).to eq(true)
  #         expect(topic_3.reload.tags.include?(supported_tag)).to eq(true)
  #       end

  #       it "does not assign escalation tag to topics outside of the support category" do
  #         topic_1.update!(category_id: 109)
  #         ::Jobs::RemoveSupportTagJob.new.execute({})

  #         expect(topic_1.reload.tags.include?(staff_escalation_tag)).to eq(
  #           false
  #         )
  #       end

  #       it "does not assign escalation tag to topics that are closed" do
  #         topic_1.update!(category_id: 106, closed: true)
  #         ::Jobs::RemoveSupportTagJob.new.execute({})

  #         expect(topic_1.reload.tags.include?(staff_escalation_tag)).to eq(
  #           false
  #         )
  #       end

  #       it "does not assign escalation tag to topics that are unlisted" do
  #         topic_1.update!(category_id: 106, visible: false)
  #         ::Jobs::RemoveSupportTagJob.new.execute({})

  #         expect(topic_1.reload.tags.include?(staff_escalation_tag)).to eq(
  #           false
  #         )
  #       end
  #     end
  #   end

  #   context "User follow ups" do
  #     describe "#execute" do
  #       let(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
  #       let(:supported_tag) { Tag.find_or_create_by(name: "Supported") }
  #       let(:asked_user_tag) { Tag.find_or_create_by(name: "Asked-User") }
  #       let(:staff_escalation_tag) do
  #         Tag.find_or_create_by(name: "Staff-Escalation")
  #       end
  #       let(:sufficient_words_tag) do
  #         Tag.find_or_create_by(name: "Sufficient-Words")
  #       end
  #       let(:video_reply_tag) { Tag.find_or_create_by(name: "Video-Reply") }

  #       # sufficient words
  #       let(:topic_1) do
  #         Fabricate(
  #           :topic,
  #           created_at: 4.days.ago,
  #           archetype: "regular",
  #           category_id: 67
  #         )
  #       end
  #       let(:topic_2) do
  #         Fabricate(
  #           :topic,
  #           created_at: 13.days.ago,
  #           archetype: "regular",
  #           category_id: 67
  #         )
  #       end
  #       # outside widow
  #       let(:topic_3) do
  #         Fabricate(
  #           :topic,
  #           created_at: 2.hours.ago,
  #           archetype: "regular",
  #           category_id: 67
  #         )
  #       end
  #       # video tags
  #       let(:topic_4) do
  #         Fabricate(
  #           :topic,
  #           created_at: 5.days.ago,
  #           archetype: "regular",
  #           category_id: 67
  #         )
  #       end
  #       # wrong category
  #       let(:topic_5) do
  #         Fabricate(
  #           :topic,
  #           created_at: 5.days.ago,
  #           archetype: "regular",
  #           category_id: 109
  #         )
  #       end
  #       # has asked user custom field
  #       let(:topic_6) do
  #         Fabricate(
  #           :topic,
  #           created_at: 5.days.ago,
  #           archetype: "regular",
  #           category_id: 67
  #         )
  #       end

  #       before do
  #         topic_6.custom_fields["asked_user"] = true
  #         topic_6.save!
  #         topic_4.tags << video_reply_tag
  #         Post.create!(
  #           user_id: Fabricate(:user).id,
  #           raw: ("Hello ") * 200,
  #           topic_id: topic_1.id
  #         )
  #         Post.create!(
  #           user_id: Fabricate(:user).id,
  #           raw: ("Hello ") * 200,
  #           topic_id: topic_1.id
  #         )
  #         Post.create!(
  #           user_id: Fabricate(:user).id,
  #           raw: ("Hello ") * 200,
  #           topic_id: topic_2.id
  #         )
  #         Post.create!(
  #           user_id: Fabricate(:user).id,
  #           raw: ("Hello ") * 200,
  #           topic_id: topic_2.id
  #         )
  #       end

  #       it "sends a follow up message to the user" do
  #         expect { ::Jobs::FollowUpSupportJob.new.execute({}) }.to change {
  #           Post.count
  #         }.by(2)
  #       end
  #     end
  #   end
  # end

  # context "Topic Tag Creation" do
  #   let(:stub_supplier) do
  #     stub_request(
  #       :post,
  #       %r{https://porter.heartsupport.com/webhooks/supplier}
  #     ).to_return(status: 200, body: "", headers: {})
  #   end
  #   let(:stub_hsapps) do
  #     stub_request(
  #       :post,
  #       %r{https://porter.heartsupport.com/twilio/discourse_webhook}
  #     ).to_return(status: 200, body: "", headers: {})
  #   end
  #   let(:topic) { Fabricate(:topic, archetype: "regular", category_id: "67") }
  #   let(:post) { Fabricate.build(:post, topic: topic, user: Fabricate(:user)) }
  #   let(:supported_tag) { Tag.find_or_create_by(name: "Supported") }
  #   let(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
  #   let(:video_reply_tag) { Tag.find_or_create_by(name: "Video-Reply") }
  #   let(:sufficient_words_tag) do
  #     Tag.find_or_create_by(name: "Sufficient-Words")
  #   end

  #   before do
  #     stub_supplier
  #     stub_hsapps
  #   end

  #   it "removed needs support tag, adds supported tag when video reply tag is added" do
  #     post.save!
  #     expect(topic.tags.include?(needs_support_tag)).to eq(true)

  #     topic.tags << video_reply_tag
  #     topic.save!

  #     expect(topic.tags.reload.include?(needs_support_tag)).to eq(false)
  #     expect(topic.tags.reload.include?(sufficient_words_tag)).to eq(true)
  #     expect(topic.tags.reload.include?(video_reply_tag)).to eq(true)
  #   end
  # end

  # context "Topic Creation" do
  #   let!(:topic) { Fabricate(:topic, archetype: "regular", category_id: "77") }
  #   let!(:need_listening_ear_tag) do
  #     Tag.find_or_create_by(name: "Need-Listening-Ear")
  #   end

  #   it "adds needs-listening-ear tag if platform topic" do
  #     expect(topic.reload.tags.include?(need_listening_ear_tag)).to eq(true)
  #   end
  # end
end
