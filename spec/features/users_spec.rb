feature 'Users' do

  # todo: password_resets

  context 'on the signup page' do

    before(:all) do
      @attrs = FactoryGirl.attributes_for(:user)
      @attrs.except!(:authenticator, :activated, :activated_at) # not settable
    end

    before(:each) do
      User.delete_all
    end

    scenario 'page should prompt user to check for activation email when user signs up correctly' do
      expect do
        visit signup_path
        sign_up_user_with @attrs

        expect(page).to have_flag('.success#user_created')
        expect(page).to have_content /please check your email/i

      end.to change(User, :count).by(1)
    end

    scenario 'activation should be required after user signs up correctly' do
      expect do
        visit signup_path
        sign_up_user_with @attrs
        expect(page).to have_content "You're almost there!"
      end.to change(ActionMailer::Base.deliveries, :count).by(1)
      expect(User.last.activated?).not_to eq(true)
    end

    scenario 'an error should be displayed when user does not specify all required attributes' do
      [:username, :password, :forename, :surname].each do |attr|
        expect do
          @attrs.merge!(attr => nil)
          visit signup_path
          sign_up_user_with @attrs
          expect(page).to have_selector('.error#user_validation_error')
        end.not_to change(User, :count)
      end
    end

    # TODO - this is redundant with users_edit_spec. Delete one of them
    scenario 'when user enters username', js: true do
      verify_uniqueness_check_by_ajax 'user_username', 'varity_user'
    end

    # TODO - this is redundant with users_edit_spec. Delete one of them
    scenario 'when user enters email', js: true do
      verify_uniqueness_check_by_ajax 'user_email', 'varity_user@varity.org'
    end

    # TODO - reconcile this with users_edit_spec password tests.
    scenario 'when password does not meet requirements' do
      expect do
        visit signup_path
        @attrs.merge!(password: 'abc')
        sign_up_user_with @attrs
        expect(page).to have_selector('.error#password_error')
      end.not_to change(User, :count)
    end

    scenario 'when password does not equal confirmation' do
      expect do
        visit signup_path
        @attrs.merge!(password: 'i_<3_grainne_godfree', password_confirmation: 'estrogen_hockey')
        sign_up_user_with @attrs
        expect(page).to have_selector('.error#password_confirmation_error')
      end.not_to change(User, :count)
    end

    scenario 'accepting the Terms of Use should be required before successfully signing up (no JS)' do
      expect do
        visit signup_path
        sign_up_user_with @attrs, accept_terms: false
      end.not_to change(User, :count)
      expect(page).to have_terms_of_use_error
    end

    scenario 'the :save button should be disabled until Terms of Use are accepted', js: true do
      visit signup_path
      expect(page).to have_css 'button#submit.disabled'
      accept_terms_of_use
      expect(page).not_to have_css 'button#submit.disabled'
      uncheck 'terms_of_use'
      expect(page).to have_css 'button#submit.disabled'
    end

    scenario 'fields should retain values on page reload after failed signup' do
      Array([:username, :password, :forename, :surname].sample).each do |attr|
        expect do
          @attrs.merge!(attr => nil)
          visit signup_path
          sign_up_user_with @attrs
          expect(page).to have_selector('.error#user_validation_error')

          # should have fields with prefilled values.
          [ :email, :title, :company, :location, :description,
            :sensitivity, :url_facebook, :url_linkedin, :url_twitter,
            :url_google_plus, :url_homepage ].each do |attr|

              value = @attrs[attr]
              expect(page).to have_field "user_#{attr}", with: value if value
          end

        end.not_to change(User, :count)
      end
    end

  end

  context 'searching for a user' do

    before(:all) do
      @firstname = 'Snoopy'
      FactoryGirl.create_list(:user, 3, firstname: @firstname)
      FactoryGirl.create_list(:user, 2)
      User.reset_search
      visit users_path
      @search_id = 'users_search'
    end

    #TODO - We should allow searching for users somehow. Maybe from a navbar?
    scenario 'should return correct results', later: true do
      search_for @firstname
      expect(page).to have_search_results :tbd
    end

  end

  context "the user's own profile page" do

    before(:all) do
      @user = FactoryGirl.create(:user, :with_everything)
      @other_user = FactoryGirl.create(:user)
    end

    scenario 'should require signin' do
      visit profile_path
      expect(current_path).to eq(sign_in_path)
    end

    scenario 'should show the profile page when signed in' do
      sign_in @user
      visit profile_path
      expect(page).to have_browser_title @user.username
      expect(page).to have_page_title @user.username
      verify_profile_information_for @user
    end


  end

  context "the 'show' (aka 'profile') page" do

    before(:all) do
      @user = FactoryGirl.create(:user, :with_everything)
      @other_user = FactoryGirl.create(:user)
    end

    before(:each) do
      visit user_path(@user)
    end

    scenario 'should have the correct browser title' do
      expect(page).to have_browser_title @user.username
    end

    scenario 'should have the correct page title' do
      expect(page).to have_page_title @user.username
    end

    scenario 'should have all the basic info' do
      verify_profile_information_for @user
    end

    scenario 'should show listed surveys' do
      @user.listed_surveys.first(5).each do |survey|
        expect(page).to have_content(survey.title)
      end
    end

    scenario 'should not allow editing unless signed in' do
      expect(page).not_to have_selector('a#edit')
    end

    scenario 'should have a button to send advice to this user' do
      # argh. only one of these links should be visible,
      # but capybara finds two of them
      first('.profile .actions a[href^="/advice/new"]').click
      expect(current_path).to match(/advice\/new/)
      expect(page).to have_css '.to .tile', text: @user.displayname
    end

    # this functionality does not work if visitor is not already signed in
    # when he clicks 'Ask Advice from Whoever'.
    # Would be very nice to have this.
    scenario 'should have a button to request advice from this user', :later do
      # argh. only one of these links should be visible,
      # but capybara finds two of them
      first('.profile .actions a[href^="/invitations/new"]').click
      expect(current_path).to eq(sign_in_path)
      sign_in @other_user
      expect(current_path).to match(/invitations\/new/)
      binding.pry
      expect(page).to have_css '.to .tile', text: @user.displayname
    end

    scenario 'should have a button to request advice from this user', :later do
      # argh. only one of these links should be visible,
      # but capybara finds two of them
      sign_in @other_user
      visit user_path(@user)
      first('.profile .actions a[href^="/invitations/new"]').click
      expect(current_path).to match(/invitations\/new/)
      expect(page).to have_css '.to .tile', text: @user.displayname
    end

    scenario 'should show a message if there are no listed surveys' do
      user = FactoryGirl.create(:user)
      visit user_path(user)
      expect(page).to have_selector('.info#no_listed_surveys')
    end

    scenario 'should allow editing if user is current_user' do
      sign_in @user
      visit user_path(@user)
      expect(page).to have_css('a#edit')
    end

    scenario 'should not allow toggling a contact unless signed in' do
      visit user_path(@other_user)
      expect(page).not_to have_css 'button.toggle-contact'
    end

    scenario 'should allow adding a contact when signed in', js: true do
      expect do
        sign_in @user
        visit user_path(@other_user)
        expect(page).to have_css 'button.add-contact'
        expect(page).not_to have_css 'button.remove-contact'
        click_on "toggle_contact_#{@other_user.id}"
        expect(page).to have_css 'button.remove-contact'
        expect(page).not_to have_css 'button.add-contact'
      end.to change(UserContact, :count).by(1)
    end

    scenario 'should allow removing a contact when signed in', js: true do
      UserContact.create owner: @user, user: @other_user
      expect do
        sign_in @user
        visit user_path(@other_user)
        expect(page).to have_css 'button.remove-contact'
        expect(page).not_to have_css 'button.add-contact'
        click_on "toggle_contact_#{@other_user.id}"
        expect(page).to have_css 'button.add-contact'
        expect(page).not_to have_css 'button.remove-contact'
      end.to change(UserContact, :count).by(-1)
    end

  end

  context 'account deletion' do

    before(:all) do
      @user = FactoryGirl.create :user
      @other_user = FactoryGirl.create :user
    end

    before(:each) do
      sign_in @user
    end

    scenario "should be available from a signed_in user's profile page" do
      visit user_path(@user)
      expect(page).to have_css '#delete_account'
    end

    scenario "should not be available on another user's profile page" do
      visit user_path(@other_user)
      expect(page).not_to have_css '#delete_account'
    end

    scenario "should redirect to the deletion confirmation page" do
      visit user_path(@user)
      page.first('#delete_account').click
      # click_on 'delete_account'
      expect(page).to have_page_title 'Delete My Account'
    end

    scenario "should allow the user to cancel on the deletion confirmation page" do
      expect do
        visit user_path(@user)
        # click_on 'delete_account'
        page.first('#delete_account').click
        click_on 'cancel'
      end.not_to change(User, :count)
    end

    scenario "should successfully delete the user's account after confirmation" do
      expect do
        visit user_path(@user)
        # click_on 'delete_account'
        page.first('#delete_account').click
        click_on 'confirm'
      end.to change(User, :count).by(-1)
    end

  end
end

def verify_profile_information_for user
  [ user.fullname,
    user.username,
    user.title_and_company,
    user.location,
    user.about ].each do |content|
      expect(page).to have_content(content)
    end
    user.social_sites.each do |site|
      expect(page).to have_css "##{site}"
    end
end

def sign_up_user_with attributes, accept_terms: true
  attributes.each do |key, value|
    case key
    when :sensitivity
      select value, from: 'user_sensitivity'
    else
      fill_in "user_#{key}", with: value
    end
  end
  accept_terms_of_use if accept_terms
  click_on 'submit'
end

def verify_uniqueness_check_by_ajax attribute, value
  visit signup_path
  expect(page).to have_css('div.ajax-success-indicator', :visible => false)
  fill_in attribute, with: value
  wait_for_ajax
  expect(page).to have_css('div.ajax-success-indicator', :visible => true)
end
