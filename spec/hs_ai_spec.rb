require "rails_helper"
require "rspec/mocks"

RSpec.describe HsAi, type: :model do
  let!(:user) { Fabricate(:active_user) }
  let!(:nate) { Fabricate(:active_user, username: "NateTriesAgain") }
  let!(:topic) do
    Fabricate(:topic, category_id: 87, archetype: "regular", user: user)
  end
  let!(:system_user) { User.find(-1) }

  let(:search_reponse) do
    {
      "results" => [
        {
          "message" => "I'm feeling really down today",
          "support" => [
            {
              "message" =>
                "I'm sorry to hear that. It's okay to feel down sometimes. What's going on?"
            }
          ]
        }
      ]
    }.to_json
  end
  let(:stub_qdrant) do
    stub_request(:get, %r{http://34.45.99.81:8080/search}).to_return(
      status: 200,
      body: search_reponse,
      headers: {
        "Content-Type" => "application/json"
      }
    )
  end
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

  let(:webhook_stub) do
    stub_request(
      :post,
      %r{https://porter.heartsupport.com/webhooks/topic_tags}
    ).to_return(status: 200, body: "", headers: {})
  end

  let(:sentiment_stub) do
    stub_request(
      :get,
      %r{https://porter.heartsupport.com/api/sentiment}
    ).to_return(status: 200, body: "", headers: {})
  end

  before do
    stub_qdrant
    stub_supplier
    stub_hsapps
    webhook_stub
    sentiment_stub
    Post.create!(
      user_id: Fabricate(:user).id,
      raw: "I'm feeling really down today",
      topic_id: topic.id
    )

    # allow(HeartSupport::HsAi).to receive(:send_dm)
    # allow(HeartSupport::HsAi).to receive(:formatted_response)
  end

  describe ".share_similar_experience" do
    before do
      allow(Post).to receive(:create!)
      allow(User).to receive(:find_by).and_return(system_user)
      allow(HsAi).to receive(:formatted_response).and_return(
        "formatted_response"
      )
      allow(Tag).to receive(:find_or_create_by).and_return(
        Fabricate(:tag, name: "Auto-Reply")
      )
      allow(PostCreator).to receive(:create).and_return(true)
    end
    it "sends a experience share" do
      expect(HsAi).to receive(:formatted_response)
      # expect(HeartSupport::HsAi).to receive(:send_dm)
      expect(PostCreator).to receive(:create)
      HsAi.share_similar_experience(topic)
    end
  end

  describe ".send_dm" do
    let!(:title) do
      "Similar Experience Found for topic: #{topic.title} with id: #{topic.id}"
    end
    let!(:user_reply) do
      "Hi, I'm feeling really down today I'm sorry to hear that. It's okay to feel down sometimes. What's going on?"
    end
    let!(:target_usernames) { [nate.username] }

    it "increments Post count" do
      expect { HsAi.send_dm(target_usernames, user_reply, title) }.to change {
        Post.count
      }.by(1)
    end
  end
end
