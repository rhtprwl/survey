# == Schema Information
#
# Table name: surveys
#
#  id              :integer         not null, primary key
#  category_id     :integer         not null
#  title           :string          not null
#  owner_id        :integer         not null
#  created_at      :datetime        not null
#  updated_at      :datetime        not null
#  description     :text
#  responses_count :integer         default("0"), not null
#  instructions    :text
#  draft           :boolean         not null
#  post_id         :integer
#  private         :boolean         default("f"), not null
#



describe Survey do

  describe 'shared examples' do

    it_should_behave_like 'a cloneable object'
    it_should_behave_like 'a searchable model', :elastic_search

  end

  describe 'basics' do

    before(:all) do
      @user1 = FactoryGirl.build_stubbed(:user)
      @survey1 = FactoryGirl.build_stubbed(:survey)
      @attr = FactoryGirl.attributes_for(:survey)
    end

    it "should create a new instance given a valid attribute" do
      Survey.create!(@attr)
    end

    it "should require a valid title" do
      expect(Survey.new(@attr.merge(:title => ""))).not_to be_valid
      expect(Survey.new(@attr.merge(:title => "x"*151))).not_to be_valid
    end

    # avoid saving the survey if all it has is the default title,
    # e.g. 'Untitled Survey'.
    # Shit. We have to allow this so that draft dummy surveys can be created
    # in the surveys/edit action (which in turn is required because we create
    # a dummy question to go with it).
    it "should not save with the default ('Untitled') title", :deprecated do
      expect(Survey.new(@attr.merge(title: Survey::DEFAULT_TITLE))).not_to be_valid
    end

    it "should require an owner" do
      expect(Survey.new(@attr.merge(:owner_id => ""))).not_to be_valid
    end

    it "should belong to missing_user if the owner is missing" do
      owner = @survey1.owner
      User.delete(owner.id)
      expect(@survey1.owner.username).to eq(User.missing_user.username)
    end

    it "should require a description" do
      expect(Survey.new(@attr.merge(:description => ""))).not_to be_valid
    end

    # it "should default to the default category on bad category assignments" do
    # 	# Note: dubious design. This is for convenience in the view when assigning Survey.new. Revisit this.
    # 	expect(Survey.new(@attr.merge(:category_id => nil)).category).to eq(Category.default)
    # 	expect(Survey.new(@attr.merge(:category_id => -1)).category).to eq(Category.default)
    # end

    it "should always report the correct questions_count" do
      survey = Survey.create!(@attr)
      FactoryGirl.create_list(:text_question, 2, survey_id: survey.id)
      FactoryGirl.create_list(:multiple_choice_question, 3, survey_id: survey.id)
      FactoryGirl.create_list(:likert_question, 1, survey_id: survey.id)
      expect(survey.questions_count).to eq(6)
    end

    it 'should belong to the default category if category is not specified', ignore: true do
      # category_id now constrained to be non-nil
      survey = Survey.create! @attr.merge(category_id: nil, draft: true)
      expect(survey.category.id).to eq(Category.default.id)
    end

    it 'should not raise error if category is not specified' do
      # default category should be assigned when category is not specified
      expect{ Survey.create! @attr.merge(category_id: nil) }.not_to raise_error
      survey = Survey.create! @attr.merge(category_id: nil)
      expect(survey.category.id).to eq(Category.default.id)
    end

    it 'should not allow multiple surveys for the same post' do
      post = FactoryGirl.create(:post)
      FactoryGirl.create :survey, post_id: post.id
      expect{ FactoryGirl.create :survey, post_id: post.id }.to raise_error
    end

    it 'should have an updated responses_count after sent with a counsel', ignore: true do
      # see counsel_spec
    end

  end

  describe 'pages' do

    before :each do
      @survey = FactoryGirl.create :survey, questions_count: 5
    end

    it 'should work correctly with no page breaks' do
      expect(@survey.page(1).questions.count).to eq(5)
      expect(@survey.page(1).untitled?).to be(true)
      expect(@survey.questions.count).to eq(5)
      expect(@survey.page_count).to eq(1)
    end

    it 'should work correctly with an implicit first page' do
      @survey.insert_page_break \
        title: 'Foo Foo Foo',
        description: 'bar bar bar',
        before: 3

      expect(@survey.questions.count).to eq(5)
      expect(@survey.page_count).to eq(2)

      expect{@survey.page(0)}.to raise_error

      expect(@survey.page(1).questions.count).to eq(2)
      expect(@survey.page(1).untitled?).to be(true)

      expect(@survey.page(2).questions.count).to eq(3)
      expect(@survey.page(2).untitled?).to be(false)
      expect(@survey.page(2).title).to eq('Foo Foo Foo')
      expect(@survey.page(2).description).to eq('bar bar bar')

      expect(@survey.page(3)).to be(nil)
    end

    it 'should work correctly with adjacent page breaks (with no intervening questions)' do

      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 3
      @survey.insert_page_break \
        title: 'Foo 2',
        description: 'bar 1',
        before: 3
      @survey.insert_page_break \
        title: 'Foo 2',
        description: 'bar 1',
        before: 3

      # order of adjacent page breaks is not guaranteed, for now

      expect(@survey.page_count).to eq(4)
      expect(@survey.page(1).questions.count).to eq(2)
      expect(@survey.page(2).questions.count).to eq(0)
      expect(@survey.page(3).questions.count).to eq(0)
      expect(@survey.page(4).questions.count).to eq(3)
    end

    it 'should work correctly with a single page break at the end' do

      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 6

      expect(@survey.page_count).to eq(2)
      expect(@survey.page(1).questions.count).to eq(5)
      expect(@survey.page(2).questions.count).to eq(0)
    end

    it 'should work correctly with adjacent page breaks at the end' do

      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 6
      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 6
      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 6

      expect(@survey.page_count).to eq(4)
      expect(@survey.page(1).questions.count).to eq(5)
      expect(@survey.page(2).questions.count).to eq(0)
      expect(@survey.page(3).questions.count).to eq(0)
      expect(@survey.page(4).questions.count).to eq(0)
    end

    it 'should work correctly with a single page break at the beginning' do

      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 1

      expect(@survey.page_count).to eq(1)
      expect(@survey.page(1).questions.count).to eq(5)
      expect(@survey.page(2)).to be(nil)
    end

    it 'should work correctly with adjacent page breaks at the beginning' do

      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 1
      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 1
      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 1

      expect(@survey.page_count).to eq(3)
      expect(@survey.page(1).questions.count).to eq(0)
      expect(@survey.page(2).questions.count).to eq(0)
      expect(@survey.page(3).questions.count).to eq(5)
      expect(@survey.page(4)).to be(nil)
    end

    it 'should work correctly with several page breaks' do

      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 1
      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 3
      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 3
      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 5
      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 6
      @survey.insert_page_break \
        title: 'Foo 1',
        description: 'bar 1',
        before: 6

      # <break> 1 2 <break> <break> 3 4 <break> 5 <break> <break>

      expect(@survey.page_count).to eq(6)
      expect(@survey.page(1).questions.count).to eq(2)
      expect(@survey.page(2).questions.count).to eq(0)
      expect(@survey.page(3).questions.count).to eq(2)
      expect(@survey.page(4).questions.count).to eq(1)
      expect(@survey.page(5).questions.count).to eq(0)
      expect(@survey.page(6).questions.count).to eq(0)
    end

  end

  describe 'scopes' do

    before(:all) do
      @user = FactoryGirl.create(:user)
      @public_survey = FactoryGirl.create(:survey)
      @posted_survey = FactoryGirl.create(:posted_survey)
      @user_private_survey = FactoryGirl.create(:private_survey, owner_id: @user.id)
      @other_user_private_survey = FactoryGirl.create(:private_survey, owner_id: FactoryGirl.create(:user).id)
    end

    it 'should return only public surveys' do
      surveys = Survey.publick
      verify_inclusion surveys, [@public_survey, @posted_survey], true
      verify_inclusion surveys, [@user_private_survey, @other_user_private_survey], false
    end

    it 'should return only surveys that are viewable by a user' do
      surveys = Survey.viewable_by(@user)
      verify_inclusion surveys, [@public_survey, @posted_survey, @user_private_survey], true
      verify_inclusion surveys, [@other_user_private_survey], false
    end

    it 'should return only public surveys if no user' do
      surveys = Survey.viewable_by(nil)
      verify_inclusion surveys, [@public_survey, @posted_survey], true
      verify_inclusion surveys, [@user_private_survey, @other_user_private_survey], false
    end

    it 'should return only posted surveys' do
      surveys = Survey.posted
      verify_inclusion surveys, [@posted_survey], true
      verify_inclusion surveys, [@public_survey, @user_private_survey, @other_user_private_survey], false
    end

    it 'should return only public non posted surveys' do
      surveys = Survey.posted(false)
      verify_inclusion surveys, [@public_survey], true
      verify_inclusion surveys, [@posted_survey, @user_private_survey, @other_user_private_survey], false
    end

    it 'should return specified number of top surveys' do
      expect(Survey.top(1).count).to eq(1)
      expect(Survey.top(2).count).to eq(2)
    end

    it 'should return only public surveys in top surveys' do
      surveys = Survey.top(500)
      verify_inclusion surveys, [@public_survey, @posted_survey], true
      verify_inclusion surveys, [@user_private_survey, @other_user_private_survey], false
    end
  end

  describe 'listed surveys' do

    before(:all) do
      @user1 = FactoryGirl.create(:user)
      @survey1 = FactoryGirl.create(:survey)
      @attr = FactoryGirl.attributes_for(:survey)
    end

    before(:each) do
      UserListedSurvey.delete_all
      UserListedSurvey.create(user: @user1, survey: @survey1)
    end

    it 'should create a new instance with valid attributes' do
      survey = FactoryGirl.create(:survey)
      expect(UserListedSurvey.new(:user => @user1, :survey => survey)).to be_valid
    end

    it 'should not allow duplicates' do
      expect(UserListedSurvey.new(:user => @user1, :survey => @survey1)).not_to be_valid
    end

    it 'should be destroyed with the user' do
      count = @user1.listed_surveys.count
      expect{ @user1.destroy }.to change(UserListedSurvey, :count).by(-1 * count)
    end

    it 'should report its status correctly' do
      listed = @survey1
      unlisted = FactoryGirl.create(:survey)
      expect(@user1.has_listed? listed).to be true
      expect(@user1.has_listed? unlisted).to be false
    end
  end

  describe 'favorite surveys' do

    before(:all) do
      @user1 = FactoryGirl.create(:user)
      @survey1 = FactoryGirl.create(:survey)
      @attr = FactoryGirl.attributes_for(:survey)
    end

    before(:each) do
      UserFavoriteSurvey.delete_all
      UserFavoriteSurvey.create(user: @user1, survey: @survey1)
    end

    it 'should create a new instance with valid attributes' do
      survey = FactoryGirl.create(:survey)
      expect(UserFavoriteSurvey.new(:user => @user1, :survey => survey)).to be_valid
    end

    it 'should not allow duplicates' do
      expect(UserFavoriteSurvey.new(:user => @user1, :survey => @survey1)).not_to be_valid
    end

    it 'should be destroyed with the user' do
      count = @user1.favorite_surveys.count
      expect{ @user1.destroy }.to change(UserFavoriteSurvey, :count).by(-1 * count)
    end

    it 'should report its status correctly' do
      favorite = @survey1
      unfavorite = FactoryGirl.create(:survey)
      expect(@user1.has_favorite? favorite).to be true
      expect(@user1.has_favorite? unfavorite).to be false
    end
  end

  describe 'editing a survey' do
    describe 'duplicating a question' do

      # now covered in question_spec

    end
  end

end

def verify_inclusion surveys, surveys_array, exists
  surveys_array.each do |survey|
    expect(surveys.exists?(survey.id)).to eq(exists)
  end
end
