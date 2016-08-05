include SurveysHelper

feature 'user visits surveys index page' do

  before(:all) do
    @user = FactoryGirl.create(:user)
  end

  before(:each) do
    sign_in(@user)
    visit surveys_path
  end

  describe 'it should not have javascript errors' do
    it_should_not_have_javascript_errors
  end

end

feature 'on the surveys index page' do

  feature 'when not logged in' do

    before(:all) do
      @user = FactoryGirl.create(:user)
    end

    after(:all) do
      Survey.delete_all
      # destroy survey created in :create_survey
    end

    [ [:authored_surveys, url_helpers.surveys_path(s: 'authored')],
      [:listed_surveys, url_helpers.surveys_path(s: 'listed')],
      [:favorite_surveys, url_helpers.surveys_path(s: 'favorite')],
      [:create_survey, url_helpers.new_survey_path],
    ].each do |link, path|
      scenario "#{link} link should require a sign_in", js: true do
        visit surveys_path
        click_on link.to_s
        expect(page).to display_signin_modal
        modal_sign_in @user
        expect(current_fullpath).to eq(path)
      end

    end

    scenario "should see public surveys only" do
      absent = FactoryGirl.create(:private_survey)
      visit surveys_path
      verify_absence_of survey: absent
      present = FactoryGirl.create(:survey)
      visit surveys_path
      verify_presence_of survey: present
    end

  end

  feature 'searching' do

    before(:all) do
      @common_query = 'All Quiet on the Western Front'
      FactoryGirl.create :survey, title: 'not this one'
      FactoryGirl.create_list :survey, 3, title: @common_query
      Survey.reset_search
      @search_id = 'surveys_search'
    end

    after(:all) { Survey.destroy_all }

    scenario 'should display default results consistent with page content' do
      visit surveys_path
      expect(page).to have_consistent_query_results_message
    end

    scenario 'should return correct results for a single match' do
      visit surveys_path
      query = unique_query_for(Survey.first)
      search_for query
      _results, results_count = Survey.search(query)
      expect(_results.count).to eq(1)
      expect(results_count).to eq(1)
      expect(page).to have_consistent_query_results_message(total: results_count)
      verify_presence_of survey: Survey.first
      verify_absence_of survey: Survey.last
    end

    scenario 'should return correct results for multiple matches' do
      visit surveys_path
      query = @common_query
      search_for query
      _results, results_count = Survey.search(query)
      expect(_results.count).to eq(3)
      expect(results_count).to eq(3)
      expect(page).to have_consistent_query_results_message(total: 3)
      Survey.last(3).each do |survey|
        verify_presence_of survey: survey
      end
      verify_absence_of survey: Survey.first
    end


    scenario 'should display a useful message when no surveys are returned' do
      visit surveys_path
      query = 'elbow quartet laser hedgehog'
      search_for query
      verify_no_surveys(:query, query)
    end

    # TODO - more elasticsearch tests
  end

  feature 'private surveys' do
    before(:all) do
      @user = FactoryGirl.create(:user)
      sign_in(@user)
      @public_survey = FactoryGirl.create(:survey)
      @user_private_survey = FactoryGirl.create(:private_survey, owner_id: @user.id)
      @other_user_private_survey = FactoryGirl.create(:private_survey, owner_id: FactoryGirl.create(:user).id)
    end

    after(:all) do
      Survey.delete_all
    end

    scenario "user should see only his private surveys along with public surveys" do
      visit surveys_path
      verify_presence_of survey: @public_survey
      verify_presence_of survey: @user_private_survey
      verify_absence_of survey: @other_user_private_survey
    end
  end

  feature 'all surveys' do

    before(:all) do
      FactoryGirl.create_list(:survey, 3)
    end

    scenario 'should have the correct browser title' do
      visit surveys_path
      expect(page).to have_browser_title surveys_index_browser_title(:all)
    end

    scenario 'should have the correct page title' do
      visit surveys_path
      expect(page).to have_page_title surveys_index_page_title(:all)
    end
  end

  feature 'authored surveys' do

    before(:all) do
      @user = FactoryGirl.create(:user)
      FactoryGirl.create_list(:survey, 3, owner: @user)
      Survey.reset_search
    end

    scenario 'should have the correct browser title' do
      sign_in(@user)
      visit surveys_path(s: 'authored')
      expect(page).to have_browser_title surveys_index_browser_title(:authored)
    end

    scenario 'should have the correct page title' do
      sign_in(@user)
      visit surveys_path(s: 'authored')
      expect(page).to have_page_title surveys_index_page_title(:authored)
    end

    scenario "should not be an option when user is not signed in" do
      visit surveys_path
      expect(page).not_to have_css 'authored_surveys'
    end

    scenario "should be absent when user has no authored surveys" do
      user_with_no_surveys = FactoryGirl.create(:user)
      sign_in user_with_no_surveys
      visit surveys_path
      click_on :authored_surveys
      verify_no_surveys(:authored)
    end

    scenario "should be present when user has authored surveys" do
      authored_survey = FactoryGirl.create(:survey, owner: @user)
      other_user = FactoryGirl.create(:user)
      unauthored_survey = FactoryGirl.create(:survey, owner: other_user)
      Survey.reset_search
      sign_in @user
      visit surveys_path
      click_on :authored_surveys
      verify_presence_of survey: authored_survey
      verify_absence_of survey: unauthored_survey
    end

  end # authored surveys

  [:favorite, :listed].each do |survey_type|

    table = "user_#{survey_type}_survey".classify.constantize

    feature "#{survey_type} surveys" do

      before(:all) do
        @user = FactoryGirl.create(:user)
        FactoryGirl.create_list(:survey, 3, owner: @user)
        Survey.reset_search
      end

      scenario 'should have the correct browser title' do
        sign_in(@user)
        visit surveys_path(s: "#{survey_type}")
        expect(page).to have_browser_title surveys_index_browser_title(survey_type.to_sym)
      end

      scenario 'should have the correct page title' do
        sign_in(@user)
        visit surveys_path(s: "#{survey_type}")
        expect(page).to have_page_title surveys_index_page_title(survey_type.to_sym)
      end

      scenario 'should not be a clickable option when user is not signed in' do
        visit surveys_path
        expect(page).not_to have_css "#{survey_type}_surveys"
      end

      scenario "should be absent when user has no #{survey_type} surveys" do
        sign_in(@user)
        visit surveys_path
        click_on "#{survey_type}_surveys"
        verify_no_surveys(:survey_type)
      end

      scenario "should be present when user has #{survey_type} surveys" do
        sign_in(@user)
        present_survey = FactoryGirl.create( "user_#{survey_type}_survey",
                          user: @user,
                          survey: Survey.first
                           ).survey
        absent_survey = FactoryGirl.create(:survey)
        Survey.reset_search
        visit surveys_path
        click_on "#{survey_type}_surveys"
        verify_presence_of survey: present_survey
        verify_absence_of survey: absent_survey
      end

      # toggle_javascript_scenario \ # non-js no longer supported ~ rct 2015.11.04
      scenario "should update when user adds a new #{survey_type} survey", js: true do
        sign_in(@user)
        table.destroy_all
        visit surveys_path
        expect do
          survey = Survey.first
          page.find("a[id='add_#{survey_type}_#{survey.id}']").click
          expect(page).to have_selector(".success#added_#{survey_type}_survey")
          expect(page).to have_selector("a[id='remove_#{survey_type}_#{survey.id}']")
        end.to change(table, :count).by(1)
      end

      # toggle_javascript_scenario \ # non-js no longer supported ~ rct 2015.11.04
      scenario "should update when user removes a #{survey_type} survey", js: true do
        sign_in(@user)
        survey = Survey.first
        FactoryGirl.ensure("#{survey_type}_survey", user_id: @user.id, survey: survey)
        visit surveys_path
        expect do
          page.find("a[id='remove_#{survey_type}_#{survey.id}']").click
          expect(page).to have_selector(".success#removed_#{survey_type}_survey")
          expect(page).to have_selector("a[id='add_#{survey_type}_#{survey.id}']")
        end.to change(table, :count).by(-1)
      end
    end
  end # listed, favorite surveys

  feature 'filtering by target listed surveys' do

    feature 'when there is a target user with listed surveys' do

      before(:all) do
        @user = FactoryGirl.create(:user)
        UserListedSurvey.delete_all
        @listed_surveys = []
        3.times do
          survey = FactoryGirl.create(:survey)
          @listed_surveys.append FactoryGirl.create(UserListedSurvey, user: @user, survey: survey).survey
        end
        @unlisted_surveys = FactoryGirl.create_list(:survey, 3)
        # Survey.reset_search
      end

      before(:each) do
        visit new_advice_path
        fill_in 'user_input_recipients', with: @user.username
        click_on 'choose_survey'
        click_on 'tlisted_surveys'
      end

      # NOTE: all state (session, page, etc.) is cleared between tests.

      scenario 'should have the correct browser title' do
        expect(page).to have_browser_title surveys_index_browser_title(:tlisted, target_user: @user)
      end

      scenario 'should have the correct page title' do
        expect(page).to have_page_title surveys_index_page_title(:tlisted, target_user: @user)
      end

      scenario "should display the correct surveys", elasticsearch: true do
        @listed_surveys.each { |s| expect(page).to have_css('#surveys-index .title', text: s.title) }
        @unlisted_surveys.each { |s| expect(page).not_to have_css('#surveys-index .title', text: s.title) }
      end

    end

    feature 'when there is a target user with no listed surveys' do

      before(:all) do
        @user = FactoryGirl.create(:user)
      end

      scenario 'should not be be an available option' do
        visit new_advice_path
        fill_in 'user_input_recipients', with: @user.username
        click_on 'choose_survey'
        expect(page).not_to have_css('#tlisted_surveys')
      end

    end

    feature 'when there is no target user' do

      before(:all) do
        clear_session
      end

      scenario 'should not be an available option' do
        visit new_advice_path
        expect(page).not_to have_css('#tlisted_surveys')
      end
    end

  end # target listed surveys

  feature 'pagination' do

    before(:all) do
      Survey.delete_all
      Survey.reset_search
      FactoryGirl.create_list(:survey, Survey::PER_PAGE - 2)
    end

    scenario 'should not happen without sufficient surveys' do
      visit surveys_path

      # page should actually have the right number of surveys
      expect(page.all('.survey-summaries > .survey-summary-row').count).to \
        eq(Survey.count)
      expect(page).to have_css '.survey-summaries',
        text: Survey.first.description.first(40)

      # page should claim to be showing the right number of surveys
      expect(page).to have_consistent_query_results_message(
        total: Survey::PER_PAGE - 2)

      # the pagination stuff should not be there
      expect(page).not_to have_css('.pagination')
    end

    scenario 'should work without javascript', :elasticsearch do

      FactoryGirl.create_list(:survey, 3) # bump up over page limit
      Survey.reset_search
      visit surveys_path

      text_of_survey_on_page_one = Survey.first.description.first(50)
      text_of_survey_on_page_two = Survey.last.description.first(50)

      _records, records_count = Survey.search
      expect(records_count).to eq(Survey.count)

      # note: records.last returns highest id, not actually the last element in
      # the records 'array'

      # page should actually have the right number of surveys
      expect(page.all('.survey-summaries > .survey-summary-row').count).to \
        eq(Survey::PER_PAGE)
      expect(page).to have_css '.survey-summaries',
        text: text_of_survey_on_page_one

      # page should claim to be showing the right number of surveys
      expect(page).to have_consistent_query_results_message(total: Survey.count)

      # the pagination stuff should be there
      expect(page).to have_css('.pagination .last')
      expect(page).not_to have_css('.pagination .prev')

      # records on the second page should not show up (yet)
      expect(page).not_to have_css '.survey-summaries',
        text: text_of_survey_on_page_two

      # go to page 2
      find('.pagination .last a').click

      # pagination stuff should still be there
      expect(page).to have_css('.pagination .prev')
      expect(page).not_to have_css('.pagination .last')

      # ... as well as the record in question
      expect(page).to have_css '.survey-summaries',
        text: text_of_survey_on_page_two

      # ... and the correct query results message
      expect(page).to have_consistent_query_results_message(
        page_num: 2, total: Survey.count )
    end

    # infinite scrolling worked fine but is not broken inexplicably. Fuck it.
    scenario 'should work with javascript (infinite scrolling)', js: true, tbd: true do
      FactoryGirl.create_list(:survey, 3) if
        (Survey.count < Survey::PER_PAGE + 1) # bump up over page limit
      Survey.reset_search
      visit surveys_path

      expect(page).to have_css '.survey-summaries',
        text: text_of_survey_on_page_one
      visit '#footer'

      expect(page).to have_css 'survery-summaries',
        text: text_of_survey_on_page_two
    end
  end # pagination

  feature 'sorting and filtering', :tbd do

    before(:all) do
      @cat_1_surveys = FactoryGirl.create_list(:survey, 2, category_id: 1)
      @cat_2_surveys = FactoryGirl.create_list(:survey, 2, category_id: 2)
    end

    scenario 'when user selects a category', js: true, wtf: true do
      visit surveys_path
      @cat_1_surveys.concat( @cat_2_surveys ).each do |survey|
        expect(page).to have_css '.survey .title', text: survey.title
      end

      find('#category option[value="1"]').select_option
      # sleep 10
      # wtf. This works fine in browser but does not reload page here.

      @cat_1_surveys.each do |survey|
        expect(page).to have_css '.survey .title', text: survey.title
      end
      @cat_2_surveys.each do |survey|
        expect(page).not_to have_css '.survey .title', text: survey.title
      end
    end

    scenario "when user filters with multiple criteria", :tbd do
    end
  end # sorting and filtering

  feature 'the survey sidebar' do

    # this test should cover hot_surveys, popular_surveys, etc

    before(:all) do
      FactoryGirl.create_list(:survey, 3)
      @user = FactoryGirl.create(:user)
      # Survey.reset_search
    end

    scenario 'should contain working links to survey detail pages' do

      [surveys_path, new_solicitation_path, new_advice_path].each do |path|
        sign_in(@user)
        visit path
        a = all('.survey-list li.survey > a')[2]
        survey = Survey.find Rails.application.routes.recognize_path(a[:href])[:id]
        a.click
        expect(current_path).to eq(survey_path(survey))
        expect(page).to have_content(survey.description.first(100))
      end
    end

  end # survey sidebar

  feature "the 'attach' button" do

    before(:all) do
      FactoryGirl.create :survey
      # Survey.reset_search
      @user = FactoryGirl.create(:user)
    end

    before(:each) do
      sign_in @user
    end

    scenario 'should not be displayed unless currently in survey_select_mode' do
      new_message_path = [new_advice_path, new_solicitation_path].sample
      visit new_message_path

      # clicking 'cancel' unsets the survey_select_mode
      click_on 'cancel'

      visit surveys_path
      expect(page).not_to have_css 'a.attach'
    end

    scenario 'should be displayed when in survey_select_mode' do
      new_message_path = [new_advice_path, new_solicitation_path].sample
      visit new_message_path
      visit new_solicitation_path
      visit surveys_path
      expect(page).to have_css 'a.attach'
    end

    scenario 'should not be displayed after the select_mode expires', faith: true do
      # survey_select_mode should expire after some number of seconds
      # don't know how to test this without messing the the session, which requires
      # an additional gem and is too much trouble
    end

  end

end
