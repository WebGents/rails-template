FactoryGirl.define do
  factory :user do
    person
    password { Faker::Internet.password(20) }
    email { person.email }
    after(:build) { |a| a.add_role :viewer }
    confirmed_at { 1.day.ago }

    trait :superuser do
      after(:build) { |a| a.add_role :superuser }
    end

    trait :admin do
      after(:build) { |a| a.add_role :admin }
    end

    trait :guest do
      after(:build) { |a| a.add_role :guest }
    end

    trait :with_identity do
      after(:create) do |obj|
        ident = Identity.from_oauth build(:oauth)
        ident.user = obj
        ident.save!
      end
    end
  end
end
