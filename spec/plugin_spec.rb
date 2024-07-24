require "rails_helper"
require "rspec/mocks"

RSpec.describe HeartSupport::Support, type: :model do
  # before each clears the database
  #  # before { allow(HeartSupport).to receive(:set_resolution_tag) }
  let(:stub_supplier) do
    stub_request(
      :post,
      %r{https://porter.heartsupport.com/webhooks/supplier}
    ).to_return(status: 200, body: "", headers: {})
  end
  let(:stub_hsapps) do
    stub_request(
      :post,
      %r{https://porter.heartsupport.com/twilio/discourse_webhook}
    ).to_return(status: 200, body: "", headers: {})
  end

  before do
    stub_supplier
    stub_hsapps
  end
  describe "#set_resolution_tag" do
    let!(:user) { Fabricate(:active_user) }
    let!(:topic) do
      Fabricate(:topic, category_id: 67, archetype: "regular", user: user)
    end

    let!(:trained_reply_tag) { Tag.find_or_create_by(name: "Trained-Reply") }
    let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
    let!(:sufficient_Words_tag) do
      Tag.find_or_create_by(name: "Sufficient-Words")
    end
    let!(:admin_selected_tag) { Tag.find_or_create_by(name: "Admin-Selected") }

    context "when tag is low in priority" do
      before do
        topic.tags << trained_reply_tag
        topic.save!
        topic.reload
      end

      it "does not add the needs support tag" do
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
        topic.reload
      end

      it "removes the trained reply tag and adds the admin selected tag" do
        expect(topic.tags.include?(trained_reply_tag)).to eq(true)
        HeartSupport.set_resolution_tag(topic, "Admin-Selected")
        expect(topic.reload.tags.include?(trained_reply_tag)).to eq(false)
        expect(topic.reload.tags.include?(admin_selected_tag)).to eq(true)
      end
    end
  end

  describe "#add_topic_tag" do
    let!(:user) { Fabricate(:active_user) }
    let!(:topic) do
      Fabricate(:topic, category_id: 67, archetype: "regular", user: user)
    end
    let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }

    it "adds the tag to the topic" do
      expect(topic.tags).to be_empty
      HeartSupport.add_topic_tags(topic, "Needs-Support")
      expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
    end
  end

  describe "#remove_topic_tag" do
    let!(:user) { Fabricate(:active_user) }
    let!(:topic) do
      Fabricate(:topic, category_id: 67, archetype: "regular", user: user)
    end
    let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }

    before do
      topic.tags << needs_support_tag
      topic.save!
      topic.reload
    end

    it "removes the tag from the topic" do
      expect(topic.tags.include?(needs_support_tag)).to eq(true)
      HeartSupport.remove_topic_tags(topic, "Needs-Support")
      expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
    end
  end

  context "Discourse Events" do
    let(:topic) do
      Fabricate(
        :topic,
        category_id: 67,
        archetype: "regular",
        user: Fabricate(:active_user)
      )
    end
    let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }

    before do
      topic.tags << needs_support_tag
      topic.save!
      topic.reload
    end

    context "when the topic is closed" do
      it "removes the needs support tag" do
        expect(topic.tags.include?(needs_support_tag)).to eq(true)
        topic.update!(closed: true)
        DiscourseEvent.trigger(:topic_status_updated, topic, "closed", "closed")
        expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
      end
    end

    context "when the topic is archived" do
      it "removes the needs support tag" do
        expect(topic.tags.include?(needs_support_tag)).to eq(true)
        topic.update!(visible: false)
        DiscourseEvent.trigger(
          :topic_status_updated,
          topic,
          "visible",
          "visible"
        )
        expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
      end
    end
  end

  describe "Background Jobs" do
    describe "#RemoveSupportTagJob" do
      describe "#execute" do
        let!(:topic) do
          Fabricate(
            :topic,
            category_id: 67,
            archetype: "regular",
            user: Fabricate(:active_user),
            created_at: 14.days.ago,
            closed: false,
            deleted_at: nil
          )
        end
        let!(:needs_support_tag) do
          Tag.find_or_create_by(name: "Needs-Support")
        end
        let!(:supported_tag) { Tag.find_or_create_by(name: "Supported") }

        before do
          topic.tags << needs_support_tag
          topic.save!
          topic.reload
        end

        context "when supported or deleted" do
          it "does not remove needs supported tag when deleted" do
            topic.update!(deleted_at: Time.now)

            ::Jobs::RemoveSupportTagJob.new.execute({})
            expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
          end

          it "does not remove needs supported tags when supported" do
            topic.tags << supported_tag
            topic.save!
            topic.reload

            ::Jobs::RemoveSupportTagJob.new.execute({})
            expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
          end
        end

        context "when not supported or deleted" do
          let!(:insuffficient) { Tag.find_or_create_by(name: "Insufficient") }
          let!(:supported_tag) { Tag.find_or_create_by(name: "Supported") }
          let!(:video_reply_tag) { Tag.find_or_create_by(name: "Video-Reply") }
          let!(:sufficient_words_tag) do
            Tag.find_or_create_by(name: "Sufficient-Words")
          end

          context "when word count > limit" do
            before do
              Post.create!(
                user_id: Fabricate(:user).id,
                raw: ("Hello ") * 260,
                topic_id: topic.id
              )
              Post.create!(
                user_id: Fabricate(:user).id,
                raw: ("Hello ") * 250,
                topic_id: topic.id
              )
              topic.reload
              word_count =
                topic.posts.where.not(user_id: topic.user_id).sum(:word_count)
            end
            it "removes the needs support tag and adds sufficient words, and supported tag" do
              ::Jobs::RemoveSupportTagJob.new.execute({})
              expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
              expect(topic.reload.tags.include?(supported_tag)).to eq(true)
              expect(topic.reload.tags.include?(sufficient_words_tag)).to eq(
                true
              )
            end
          end

          context "when topic has video tag" do
            before do
              topic.tags << video_reply_tag
              topic.save!
              topic.reload
            end
            it "removes the needs support tag and adds sufficient words, and supported tag" do
              ::Jobs::RemoveSupportTagJob.new.execute({})
              expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
              expect(topic.reload.tags.include?(supported_tag)).to eq(true)
              expect(topic.reload.tags.include?(sufficient_words_tag)).to eq(
                true
              )
            end
          end

          context "when word count below limit" do
            let(:insuffficient_tag) do
              Tag.find_or_create_by(name: "Insufficient")
            end
            before do
              # allow(::Jobs::RemoveSupportTagJob).to receive(
              #   :push_topic_to_supplier
              # )
              Post.create!(
                user_id: Fabricate(:user).id,
                raw: ("Hello ") * 20,
                topic_id: topic.id
              )
              Post.create!(
                user_id: Fabricate(:user).id,
                raw: ("Hello ") * 20,
                topic_id: topic.id
              )
            end
            it "removes the needs support tag and adds insufficient tag" do
              ::Jobs::RemoveSupportTagJob.new.execute({})
              expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
              expect(topic.reload.tags.include?(insuffficient_tag)).to eq(true)
              expect(stub_supplier).to have_been_requested.times(3)
            end
          end
        end
      end
    end

    describe "#FollowUpSupportJob" do
      let!(:topic) do
        Fabricate(
          :topic,
          category_id: 67,
          archetype: "regular",
          user: Fabricate(:active_user, username: "test_user"),
          created_at: 4.days.ago,
          closed: false,
          deleted_at: nil
        )
      end
      let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
      let!(:supported_tag) { Tag.find_or_create_by(name: "Supported") }
      let!(:system_user) { User.find(-1) }

      describe "#execute" do
        before do
          Post.create!(
            user_id: Fabricate(:user).id,
            raw: ("Hello ") * 20 * 10,
            topic_id: topic.id
          )
          Post.create!(
            user_id: Fabricate(:user).id,
            raw: ("Hello ") * 20 * 10,
            topic_id: topic.id
          )
        end
        context "when supported tag is present" do
          before do
            topic.tags << supported_tag
            topic.save!
            topic.reload
          end

          it "does not send a follow up message" do
            ::Jobs::FollowUpSupportJob.new.execute({})
            expect(topic.reload.custom_fields["asked_user"]).to eq(nil)
          end
        end

        context "when supported tag is not present" do
          it "sends a follow up message" do
            ::Jobs::FollowUpSupportJob.new.execute({})
            expect(topic.reload.custom_fields["asked_user"]).to eq("true")
          end
        end
      end
    end
  end

  describe "#check_responses" do
    let(:asked_user_tag) { Tag.find_or_create_by(name: "Asked-User") }
    let(:supported_tag) { Tag.find_or_create_by(name: "Supported") }
    let(:user_answered_yes_tag) do
      Tag.find_or_create_by(name: "User-Answered-Yes")
    end
    let(:user_answered_no_tag) do
      Tag.find_or_create_by(name: "User-Answered-No")
    end
    let!(:user) { Fabricate(:active_user) }
    let!(:pt_topic) do
      Fabricate(
        :topic,
        category_id: 67,
        archetype: "regular",
        user: Fabricate(:active_user),
        tags: [asked_user_tag]
      )
    end
    let!(:system_user) { User.find(-1) }
    let!(:post) do
      PostCreator.create(
        system_user,
        {
          title: "Follow Up on Your Recent Post",
          archetype: "private_message",
          target_usernames: [pt_topic.user.username],
          raw: Faker::Lorem.paragraph(sentence_count: 2),
          custom_fields: {
            ref_topic_id: pt_topic.id
          }
        }
      )
    end

    before {}

    context "when the topic is a private message" do
      context "when the respose is yes" do
        before do
          dm =
            Post.create!(
              topic_id: post.topic_id,
              user_id: pt_topic.user.id,
              raw: "yes"
            )
        end

        it "add supported, removes asked user tag and add user-answered-yes" do
          expect(pt_topic.reload.tags.include?(asked_user_tag)).to eq(false)
          expect(pt_topic.reload.tags.include?(supported_tag)).to eq(true)
          expect(pt_topic.reload.tags.include?(user_answered_yes_tag)).to eq(
            true
          )
        end
      end

      context "when the response is no" do
        before do
          dm =
            Post.create!(
              topic_id: post.topic_id,
              user_id: pt_topic.user.id,
              raw: "no"
            )
        end

        it "removes supported, add user-answered-no tag" do
          expect(pt_topic.reload.tags.include?(asked_user_tag)).to eq(false)
          expect(pt_topic.reload.tags.include?(supported_tag)).to eq(false)
          expect(pt_topic.reload.tags.include?(user_answered_no_tag)).to eq(
            true
          )
        end
      end
    end
  end

  describe "#update_tags" do
    let!(:sufficient_words_tag) do
      Tag.find_or_create_by(name: "Sufficient-Words")
    end
    let!(:staff_escalation_tag) do
      Tag.find_or_create_by(name: "Staff-Escalation")
    end
    let!(:topic) do
      Fabricate(
        :topic,
        category_id: 67,
        archetype: "regular",
        user: Fabricate(:active_user)
      )
    end

    before do
      topic.tags << staff_escalation_tag
      topic.save!
      topic.reload

      Post.create!(
        user_id: Fabricate(:user, primary_group_id: 73).id,
        raw: ("Hello ") * 20,
        topic_id: topic.id
      )
    end

    it "removes the staff escalation tag" do
      expect(topic.reload.tags.include?(staff_escalation_tag)).to eq(false)
    end
  end

  describe "#process_posts" do
    let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
    context "when first post" do
      let!(:topic) do
        Fabricate(
          :topic,
          category_id: 67,
          archetype: "regular",
          user: Fabricate(:active_user)
        )
      end
      it "adds a needs support tag" do
        expect(topic.tags).to be_empty
        Post.create!(
          user_id: Fabricate(:user).id,
          raw: ("Hello ") * 20,
          topic_id: topic.id
        )
        expect(topic.reload.tags.include?(needs_support_tag)).to eq(true)
      end
    end
    context "when not first post" do
      let!(:needs_support_tag) { Tag.find_or_create_by(name: "Needs-Support") }
      let!(:supported_tag) { Tag.find_or_create_by(name: "Supported") }
      let!(:sufficient_words_tag) do
        Tag.find_or_create_by(name: "Sufficient-Words")
      end
      let!(:staff_escalation_tag) do
        Tag.find_or_create_by(name: "Staff-Escalation")
      end
      let!(:video_reply_tag) { Tag.find_or_create_by(name: "Video-Reply") }
      let!(:topic) do
        Fabricate(
          :topic,
          category_id: 67,
          archetype: "regular",
          user: Fabricate(:active_user)
        )
      end
      before do
        Post.create!(
          user_id: Fabricate(:user).id,
          raw: ("Hello ") * 20,
          topic_id: topic.id
        )
      end
      context "when word count is below limit" do
        before do
          Post.create!(
            user_id: Fabricate(:user).id,
            raw: ("Hello ") * 20,
            topic_id: topic.id
          )
        end
        context "when replier is group member" do
          before do
            Post.create!(
              user_id: Fabricate(:user, primary_group_id: 73).id,
              raw: ("Hello ") * 20,
              topic_id: topic.id
            )
          end
          it "adds trained reply tag and supported" do
            expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
            expect(topic.reload.tags.include?(supported_tag)).to eq(true)
          end
        end
        context "when 2 swat members reply" do
          before do
            Post.create!(
              user_id: Fabricate(:user, primary_group_id: 54).id,
              raw: ("Hello ") * 20,
              topic_id: topic.id
            )
            Post.create!(
              user_id: Fabricate(:user, primary_group_id: 54).id,
              raw: ("Hello ") * 20,
              topic_id: topic.id
            )
          end
          it "adds trained reply tag and supported" do
            expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
            expect(topic.reload.tags.include?(supported_tag)).to eq(true)
          end
        end
      end
      context "when word count is above limit" do
        before do
          Post.create!(
            user_id: Fabricate(:user).id,
            raw: ("Hello, this is a test ") * 200,
            topic_id: topic.id
          )
        end
        it "adds sufficient words tags and supported tag" do
          expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
          expect(topic.reload.tags.include?(supported_tag)).to eq(true)
          expect(topic.reload.tags.include?(sufficient_words_tag)).to eq(true)
        end
      end

      context "when video reply tag is present" do
        before do
          topic.tags << staff_escalation_tag
          topic.save!
          topic.reload

          Post.create!(
            user_id: Fabricate(:user).id,
            raw: ("Hello ") * 20 + "https://www.loom.com/share",
            topic_id: topic.id
          )
        end
        it "adds sufficient words tags and supported tag" do
          expect(topic.reload.tags.include?(needs_support_tag)).to eq(false)
          expect(topic.reload.tags.include?(staff_escalation_tag)).to eq(false)
          expect(topic.reload.tags.include?(supported_tag)).to eq(true)
          expect(topic.reload.tags.include?(sufficient_words_tag)).to eq(true)
          expect(topic.reload.tags.include?(video_reply_tag)).to eq(true)
        end
      end
    end
  end

  describe "Tags Module" do
    let!(:supported_tag) { Tag.find_or_create_by(name: "Supported") }
    let!(:user_selected_tag) { Tag.find_or_create_by(name: "User-Selected") }
    let!(:need_listening_ear_tag) do
      Tag.find_or_create_by(name: "Need-Listening-Ear")
    end
    let!(:admin_selected_tag) { Tag.find_or_create_by(name: "Admin-Selected") }
    let!(:video_reply_tag) { Tag.find_or_create_by(name: "Video-Reply") }

    describe "Tags#process_tags" do
      let!(:topic) do
        Fabricate(:topic, user: Fabricate(:active_user), category_id: 102)
      end

      context "when user selected tags added" do
        before do
          topic.tags << user_selected_tag
          topic.save!
          topic.reload
        end

        it "adds the supported tag and user-selected tag" do
          expect(topic.reload.tags.include?(user_selected_tag)).to eq(true)
          expect(topic.reload.tags.include?(supported_tag)).to eq(true)
        end
      end

      context "when admin selected tags added" do
        before do
          topic.tags << admin_selected_tag
          topic.save!
          topic.reload
        end

        it "adds the supported tag and user-selected tag" do
          expect(topic.reload.tags.include?(admin_selected_tag)).to eq(true)
          expect(topic.reload.tags.include?(supported_tag)).to eq(true)
        end
      end

      context "when video tags added" do
        before do
          topic.tags << video_reply_tag
          topic.save!
          topic.reload
        end

        it "adds the supported tag and user-selected tag" do
          expect(topic.reload.tags.include?(video_reply_tag)).to eq(true)
          expect(topic.reload.tags.include?(supported_tag)).to eq(true)
        end
      end
    end

    describe "Tags#tag_platform_topics" do
      let!(:topic) do
        Fabricate(:topic, user: Fabricate(:active_user), category_id: 102)
      end

      before do
        # topic.tags << user_selected_tag
        # topic.save!
        # topic.reload
      end

      it "add the listeninig ear tag" do
        # HeartSupport::Tags.tag_platform_topic(topic)
        expect(topic.reload.tags.include?(need_listening_ear_tag)).to eq(true)
      end
    end

    describe "Tags#resolve_tags" do
    end
  end
end
