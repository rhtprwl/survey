describe User do

  it_should_behave_like 'a searchable model', indexed_fields: [
    :forename, :surname, :middlename, :email
  ]

  it_should_behave_like 'an activable model'

  before(:each) do
    @attr = FactoryGirl.attributes_for(:user)
  end

  it "should create a new instance given a valid attribute" do
    User.create!(@attr)
  end

  it "should require a username" do
    user = User.new(@attr.merge(:username => ""))
    expect(user).not_to be_valid
  end

  it "should require an authenticator" do
    user = User.create @attr
    user.authenticator = nil
    expect(user).not_to be_valid
  end

  it 'should set a default authenticator automatically' do
    user = User.create @attr.except(:authenticator)
    expect(user).to be_valid
    expect(user.authenticator).to eq User::Authenticator::LOCAL
  end

  it "should require an email address" do
    user = User.new(@attr.merge(:email => ""))
    expect(user).not_to be_valid
  end

  it "should reject names that are too long" do
    long_name = "a" * 51
    expect(User.new(@attr.merge(:forename => long_name))).not_to be_valid
    expect(User.new(@attr.merge(:surname => long_name))).not_to be_valid
    expect(User.new(@attr.merge(:middlename => long_name))).not_to be_valid
    expect(User.new(@attr.merge(:username => long_name))).not_to be_valid
  end

  it "should accept valid email addresses" do
    addresses = %w[user@foo.com THE_USER@foo.bar.org first.last@foo.jp]
    addresses.each do |address|
      valid_email_user = User.new(@attr.merge(:email => address))
      expect(valid_email_user).to be_valid
    end
  end

  it "should reject invalid email addresses" do
    addresses = %w[user@foo,com user_at_foo.org example.user@foo.]
    addresses.each do |address|
      invalid_email_user = User.new(@attr.merge(:email => address))
      expect(invalid_email_user).not_to be_valid
    end
  end

  it "should reject duplicate email addresses" do
    User.create!(@attr)
    user_with_duplicate_email = User.new(@attr)
    expect(user_with_duplicate_email).not_to be_valid
  end

  it "should reject email addresses identical up to case" do
    email = 'foobar@example.org'
    User.create @attr.merge(email: email)
    %w(Foobar@example.org FOOBAR@EXAMPLE.ORG foobar@example.ORG).each do |invalid_email|
      attrs = FactoryGirl.attributes_for :user
      expect(User.new attrs.merge(email: invalid_email)).not_to be_valid
    end
  end

  describe 'username' do

    it 'should be invalid if it is in the reserved_usernames list' do
      username = Textify.readlines('config/reserved_usernames.txt').sample
      expect(User.new @attr.merge(username: username)).not_to be_valid
    end

    it 'should be invalid if is the same as an existing username ignoring case' do
      User.create @attr.merge(username: 'florida')
      %w(Florida FLORIDA floRida floridA).each do |bad_username|
        attrs = FactoryGirl.attributes_for :user
        expect(User.new attrs.merge(username: bad_username)).not_to be_valid
      end
    end

    it 'should be invalid if it contains profanity' do
      %w(shit fuck cunt bitch).each do |curse_word|

        # pad word with stuff on either side
        curse_word.sub!( /^/, [Faker::Internet.password, ''].sample )
        curse_word.sub!( /$/, [Faker::Internet.password, ''].sample )

        expect(User.new @attr.merge(username: curse_word)).not_to be_valid
      end
    end

  end

  describe "password existence" do

    before(:each) do
      @user = User.new @attr
    end

    it "should have a password attribute" do
      expect(@user).to respond_to(:password)
    end

    it "should have a password confirmation attribute" do
      expect(@user).to respond_to(:password_confirmation)
    end
  end

  describe "password validations" do

    it "should require a non-empty password" do
      hash = @attr.merge(:password => " ", :password_confirmation => " ")
      expect(User.new(hash)).not_to be_valid
    end

    it "should require a matching password confirmation" do
      hash = @attr.merge(:password_confirmation => "invalid")
      expect(User.new(hash)).not_to be_valid
    end

    it "should require an old password on update if password was changed" do
      user = User.create @attr
      user.password = user.password_confirmation = 'new_password'
      user.save
      expect(user).not_to be_valid
    end

    it "should reject short passwords" do
      short = "a" * 5
      hash = @attr.merge(:password => short, :password_confirmation => short)
      expect(User.new(hash)).not_to be_valid
    end

    it "should reject long passwords" do
      long = "a" * 41
      hash = @attr.merge(:password => long, :password_confirmation => long)
      expect(User.new(hash)).not_to be_valid
    end
  end

  describe "password encryption" do
    # see Authenticatable

    before(:each) do
      @user = User.new @attr
    end

    it "should have an encrypted password attribute" do
      expect(@user).to respond_to(:password_digest)
    end

    it "should have a virtual password attribute " do
      expect(@user).to respond_to(:password)
    end

    it "should have a virtual password attribute " do
      expect(@user).to respond_to(:password_confirmation)
    end

    it "should set the encrypted password attribute" do
      expect(@user.password_digest).not_to be_blank
    end

    # salt deprecated (now automatically included in bcrypt password)

    describe "authenticate method" do

      it "should exist" do
        expect(@user).to respond_to(:authenticate)
      end

      it "should return nil on email/password mismatch" do
        expect(@user.authenticate('bad_password')).to be(false)
      end

      # it "should return nil for an email address with no user" do
      #   expect(User.authenticate("bar@foo.com", @attr[:password])).to be_nil
      # end

      it "should return true on email/password match" do
        expect(@user.authenticate(@attr[:password])).to be(@user)
      end
    end
  end

  describe 'omniauth' do

    before(:all) do
      @auth = mock_google_omniauth_hash
      @minimal_auth = mock_minimal_google_omniauth_hash
    end

    before(:each) do
      User.delete_all
    end

    it 'should return a valid user from a typical auth_hash' do
      user = User.from_omniauth @auth
      expect(user).to be_valid
      expect(user.authenticator).to eq(User::Authenticator::GOOGLE)

      expect(user.firstname).to eq('Brad')
      expect(user.lastname).to eq('Neely')
      expect(user.email).to eq('bneely223@gmail.com')
      expect(user.location).to eq('Hoboken, NJ')
      expect(user.username).to eq('neels')
      expect(user.image_url).to match( /.*google.*(jpg|png|jpeg)(\?sz=\d+)+$/ )
      expect(user.gender).to be User::Gender::MALE
      expect(user.url_google_plus).to eq('https://plus.google.com/+TheRealBradNeely')

      # should set a random password (unknown to user)
      expect(user.password_digest).not_to be_nil
    end

    it 'should create a valid user from a minimal auth_hash' do
      user = User.from_omniauth @minimal_auth
      expect(user).to be_valid

      expect(user.firstname).to eq('Brad')
      expect(user.lastname).to eq('Neely')
      expect(user.email).to eq('bneely223@gmail.com')

      expect(user.username).to eq('bneely223')

      expect(user.image_url).to match( /gravatar/ )
      expect(user.gender).to be User::Gender::UNKNOWN

      expect(user.authenticator).to eq(User::Authenticator::GOOGLE)

      # should set a random password (unknown to user)
      expect(user.password_digest).not_to be_nil
    end

    it 'should not persist the user' do
      expect do
        User.from_omniauth @auth
      end.not_to change(User, :count)
    end

    it 'should pick a decent default username' do
      expect(User.send :best_guess_username, @auth).to eq('neels')

      FactoryGirl.create :user, username: 'neels'
      expect(User.send :best_guess_username, @auth).to eq('bneely223')

      FactoryGirl.create :user, username: 'bneely223'
      expect(User.send :best_guess_username, @auth).to eq('TheRealBradNeely')

      FactoryGirl.create :user, username: 'TheRealBradNeely'
      expect(User.send :best_guess_username, @auth).to eq('bneely2231')
    end

  end

  describe "admin attribute" do

    before(:each) do
      @user = User.new @attr
    end

    it "should respond to admin" do
      expect(@user).to respond_to(:admin)
    end

    it "should not be an admin by default" do
      expect(@user).not_to be_admin
    end

    it "should be convertible to an admin" do
      @user.toggle!(:admin)
      expect(@user).to be_admin
    end
  end

  describe 'associated surveys' do

    let(:user) { FactoryGirl.create(:user, :with_everything) }
    let(:survey) { FactoryGirl.create(:survey) }

    it 'should report listed surveys correctly' do
      listed = user.listed_surveys.first
      unlisted = survey
      expect(user.has_listed? listed).to be true
      expect(user.has_listed? unlisted).to be false
    end

    it 'should report favorite surveys correctly' do
      favorite = user.favorite_surveys.first
      unfavorite = survey
      expect(user.has_favorite? favorite).to be true
      expect(user.has_favorite? unfavorite).to be false
    end

  end
end

# == Schema Information
#
# Table name: users
#
#  id                     :integer         not null, primary key
#  username               :string          not null
#  email                  :string          not null
#  created_at             :datetime        not null
#  updated_at             :datetime        not null
#  password_digest        :string          not null
#  admin                  :boolean         default("f"), not null
#  remember_digest        :string
#  password_reset_token   :string
#  password_reset_sent_at :datetime
#  sensitivity            :integer         not null
#  forename               :string
#  surname                :string
#  middlename             :string
#  description            :text
#  url_facebook           :string
#  url_linkedin           :string
#  url_homepage           :string
#  url_twitter            :string
#  url_google_plus        :string
#  visibility             :integer
#  gender                 :integer
#  title                  :string
#  company                :string
#  location               :string
#  mononym                :string
#
