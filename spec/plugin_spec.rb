require "rails_helper"
require "rspec/mocks"

RSpec.describe HeartSupport::Support, type: :model do
  # before each clears the database

  context "Post Creation" do
    let(:stub_supplier) { stub_request(:post, /https:\/\/porter.heartsupport.com\/webhooks\/supplier/).to_return(status: 200, body: "", headers: {}) }
    let(:stub_hsapps) { stub_request(:post, /https:\/\/porter.heartsupport.com\/twilio\/discourse_webhook/).to_return(status: 200, body: "", headers: {}) }

    context "when the post is the first post" do
      let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
      let(:user) { Fabricate(:active_user) }
      let(:topic) { Fabricate(:topic, category_id: 67, archetype: "regular", user: user) }

      before do
        stub_supplier
        stub_hsapps
      end
      it "adds the needs support tag" do
        Fabricate(:post, topic: topic)
        expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
        expect(stub_supplier).to have_been_requested.once
        expect(stub_hsapps).to_not have_been_requested
      end
    end

    context "when the post is not the first post" do
      let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
      let(:user) { Fabricate(:walter_white) }
      let(:topic) { Fabricate(:topic, category_id: 67, archetype: "regular") }
      let(:post) { Fabricate(:post, topic: topic) }
      let(:non_op_user) { Fabricate(:user) }

      before do
        stub_supplier
        stub_hsapps
      end

      it "does not add the needs support tag" do
        topic = Fabricate(:topic, category_id: 67, archetype: "regular", user: user)
        first_post = Post.create!(user_id: user.id, raw: ("Hello ") * 30, topic_id: topic.id)

        Post.create!(user_id: non_op_user.id, raw: ("Hello ") * 30, topic_id: topic.id)

        expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
        expect(first_post.is_first_post?).to eq(true)
        expect(stub_supplier).to have_been_requested.times(2)
        expect(stub_hsapps).to have_been_requested.times(1)
      end

      it "removes the needs support tag > 500 words from Non-OP users" do
        topic = Fabricate(:topic, category_id: 67, archetype: "regular", user: user)

        Post.create!(user_id: user.id, raw: ("Hello ") * 300, topic_id: topic.id)
        Post.create!(user_id: non_op_user.id, raw: ("Hello ") * 300, topic_id: topic.id)
        Post.create!(user_id: non_op_user.id, raw: ("Hello ") * 300, topic_id: topic.id)
        expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
      end

      it "does not remove the needs support tag < 500 words from Non-OP users" do
        topic = Fabricate(:topic, category_id: 67, archetype: "regular", user: user)
        Post.create!(user_id: user.id, raw: ("Hello ") * 300, topic_id: topic.id)
        Post.create!(user_id: user.id, raw: ("Hello ") * 300, topic_id: topic.id)
        Post.create!(user_id: non_op_user.id, raw: ("Hello ") * 300, topic_id: topic.id)

        expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
      end
    end
  end

  context "Private Messages" do
    let(:topic) { Fabricate(:topic, archetype: "regular") }
    let(:system_user) { User.find_by(username: "system") }
    let(:user) { Fabricate(:evil_trout) }
    let(:private_message) {
      PostCreator.create!(system_user, {
        title: "Follow Up on Your Recent Post",
        archetype: Archetype.private_message,
        target_usernames: [user.username],
        raw: Faker::Lorem.paragraph(sentence_count: 2),
        custom_fields: { ref_topic_id: topic.id },
      })
    }
    let(:pm_topic_id) { private_message.topic_id }
    let(:pm_topic) { Topic.find_by(id: pm_topic_id) }
    let(:stub_supplier) { stub_request(:post, /https:\/\/porter.heartsupport.com\/webhooks\/supplier/).to_return(status: 200, body: "", headers: {}) }
    let(:stub_hsapps) { stub_request(:post, /https:\/\/porter.heartsupport.com\/twilio\/discourse_webhook/).to_return(status: 200, body: "", headers: {}) }
    let(:stub) { stub_request(:post, /https:\/\/porter.heartsupport.com\/webhooks\/followup/).to_return(status: 200, body: "", headers: {}) }

    before do
      stub_supplier
      stub_hsapps
      stub
    end
    context "when message from user" do
      context "when the user responds yes" do
        it "responds with multiple choice" do
          expect { Post.create!(topic_id: pm_topic_id, user_id: user.id, raw: "Yes") }.to change { pm_topic.posts.count }.by(2)
          expect(stub).to_not have_been_requested
          expect(pm_topic.posts.last.raw).to include("These replies helped you (select all that apply)")
        end
      end
      context "when the user responds no" do
        it "responds with multiple choice" do
          expect {
            Post.create!(topic_id: pm_topic_id, user_id: user.id, raw: "No")
          }.to change { pm_topic.posts.count }.by(2)
          expect(stub).to_not have_been_requested
          expect(pm_topic.posts.last.raw).to include("Thank you for sharing that with us. We'll get you more support. Which of the following most applies")
          expect(topic.custom_fields["staff_escalation"]).to eq("t")
        end
      end
      context "when the user responds with neither yes or no" do
        it "send webhook request" do
          # find send a no response
          Post.create!(topic_id: pm_topic_id, user_id: user.id, raw: "No")

          # send follow up message
          expect {
            Post.create!(topic_id: pm_topic_id, user_id: user.id, raw: "This is a test random message")
          }.to change { pm_topic.posts.count }.by(1)
          expect(stub).to have_been_requested.once
        end
      end
    end
    context "when message from system" do
      let(:user) { User.find_by(username: "system") }

      it "does not get processed and receive a reply" do
        expect {
          Post.create(topic_id: pm_topic_id, user_id: user.id, raw: "This is a test random message")
        }.to change { pm_topic.posts.count }.by(1)
        expect(stub).to_not have_been_requested.once
      end
    end
  end

  context "Remove tags when topic status changes" do
    before do
      stub_supplier
      stub_hsapps
    end

    let(:stub_supplier) { stub_request(:post, /https:\/\/porter.heartsupport.com\/webhooks\/supplier/).to_return(status: 200, body: "", headers: {}) }
    let(:stub_hsapps) { stub_request(:post, /https:\/\/porter.heartsupport.com\/twilio\/discourse_webhook/).to_return(status: 200, body: "", headers: {}) }
    let(:user) { Fabricate(:newuser) }
    let(:topic) { Fabricate(:topic, category_id: 67, archetype: "regular", user: user) }
    let!(:post) { Fabricate(:post, topic: topic, user: user) }
    let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }

    context "when topic is closed" do
      before do
        stub_supplier
        stub_hsapps
      end

      it "removes the needs support tag" do
        expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
        topic.update!(closed: true)
        # send discouse event
        DiscourseEvent.trigger(:topic_status_updated, topic, "closed", "closed")
        expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
      end
    end

    context "when topic is archived" do
      before do
        stub_supplier
        stub_hsapps
      end

      it "removes the needs support tag" do
        expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
        topic.update!(visible: false)
        DiscourseEvent.trigger(:topic_status_updated, topic, "visible", "visible")
        expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
      end
    end
  end

  context "Background Jobs" do
    let(:stub_supplier) { stub_request(:post, /https:\/\/porter.heartsupport.com\/webhooks\/supplier/).to_return(status: 200, body: "", headers: {}) }
    let(:stub_hsapps) { stub_request(:post, /https:\/\/porter.heartsupport.com\/twilio\/discourse_webhook/).to_return(status: 200, body: "", headers: {}) }

    before do
      stub_supplier
      stub_hsapps
    end

    context "Clean up topics after 14 days" do
      let(:topic_1) { Fabricate(:topic, last_posted_at: 14.days.ago.beginning_of_day, archetype: "regular") }
      let(:topic_2) { Fabricate(:topic, last_posted_at: 14.days.ago, archetype: "regular") }
      let(:topic_3) { Fabricate(:topic, last_posted_at: 14.days.ago, archetype: "regular") }

      describe "#execute" do
        it "assigns the closing tags correct ly" do
          # needs_support_tag = Tag.find_or_create_by(name: "Needs-Support")
          supported_tag = Tag.find_or_create_by(name: "Supported")
          # asked_user_tag = Tag.find_or_create_by(name: "Asked-User")
          staff_escalation_tag = Tag.find_or_create_by(name: "Staff-Escalation")
          # sufficient_words_tag = Tag.find_or_create_by(name: "Sufficient-Words")
          video_reply_tag = Tag.find_or_create_by(name: "Video-Reply")

          # create posts with certain word length
          Fabricate(:post, topic: topic_1, user: Fabricate(:user))
          Fabricate(:post, topic: topic_1, user: Fabricate(:user))
          Fabricate(:post, topic: topic_2, user: Fabricate(:user), raw: ("Hello ") * 200)
          Fabricate(:post, topic: topic_2, user: Fabricate(:user), raw: ("Hello ") * 200)
          Fabricate(:post, topic: topic_3, user: Fabricate(:user), raw: ("Hello ") * 300)
          Fabricate(:post, topic: topic_3, user: Fabricate(:user), raw: ("Hello ") * 300)
          topic_1.tags << video_reply_tag

          ::Jobs::RemoveSupportTagJob.new.execute({})

          expect(topic_1.reload.tags.include?(supported_tag)).to eq(true)
          expect(topic_1.reload.tags.include?(video_reply_tag)).to eq(true)
          expect(topic_2.reload.tags.include?(staff_escalation_tag)).to eq(true)
          expect(topic_3.reload.tags.include?(supported_tag)).to eq(true)
        end
      end
    end

    context "User follow ups" do
      describe "#execute" do
        let(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
        let(:supported_tag) { Tag.find_or_create_by(name: "Supported") }
        let(:asked_user_tag) { Tag.find_or_create_by(name: "Asked-User") }
        let(:staff_escalation_tag) { Tag.find_or_create_by(name: "Staff-Escalation") }
        let(:sufficient_words_tag) { Tag.find_or_create_by(name: "Sufficient-Words") }
        let(:video_reply_tag) { Tag.find_or_create_by(name: "Video-Reply") }

        # sufficient words
        let(:topic_1) { Fabricate(:topic, created_at: 4.days.ago, archetype: "regular", category_id: 67) }
        let(:topic_2) { Fabricate(:topic, created_at: 13.days.ago, archetype: "regular", category_id: 67) }
        # outside widow
        let(:topic_3) { Fabricate(:topic, created_at: 2.hours.ago, archetype: "regular", category_id: 67) }
        # video tags
        let(:topic_4) { Fabricate(:topic, created_at: 5.days.ago, archetype: "regular", category_id: 67) }
        # wrong category
        let(:topic_5) { Fabricate(:topic, created_at: 5.days.ago, archetype: "regular", category_id: 109) }
        # has asked user custom field
        let(:topic_6) { Fabricate(:topic, created_at: 5.days.ago, archetype: "regular", category_id: 67) }

        before do
          topic_6.custom_fields["asked_user"] = true
          topic_6.save!
          topic_4.tags << video_reply_tag
          # Fabricate(:post, topic: topic_2, user: Fabricate(:user), raw: ("Hello ") * 200)
          # Fabricate(:post, topic: topic_2, user: Fabricate(:user), raw: ("Hello ") * 200)
          # Fabricate(:post, topic: topic_1, user: Fabricate(:user), raw: ("Hello ") * 200)
          # Fabricate(:post, topic: topic_1, user: Fabricate(:user), raw: ("Hello ") * 200)
          Post.create!(user_id: Fabricate(:user).id, raw: ("Hello ") * 200, topic_id: topic_1.id)
          Post.create!(user_id: Fabricate(:user).id, raw: ("Hello ") * 200, topic_id: topic_1.id)
          Post.create!(user_id: Fabricate(:user).id, raw: ("Hello ") * 200, topic_id: topic_2.id)
          Post.create!(user_id: Fabricate(:user).id, raw: ("Hello ") * 200, topic_id: topic_2.id)
        end

        it "sends a follow up message to the user" do
          expect { ::Jobs::FollowUpSupportJob.new.execute({}) }.to change { Post.count }.by(3)
        end
      end
    end
  end
end
