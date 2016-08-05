class UsersController < ApplicationController
  include ControlFreak

  before_action :authenticate,
    except: [:new, :create, :show, :check_username, :check_email]
  before_action :enforce_currrent_user, only: [:edit, :update]
  before_action :cancel, only: [:create, :update]

  layout 'no-sidebar'

  def index
    fossick

    @users, @records_count = User.search_and_page(params)
    @empty_message = [
      "Sorry, we couldn't find any users matching '#{params[:query]}'.",
      "Is there a less-specific search term you could try?"
    ]

    respond_to do |format|

      format.html do
        redirect_to root_path and return
        # nobody should be using this!
      end

      format.js do
        icon_size = params[:icon_size] || 40
        users, _records_count = User.search params[:query] # first page of results only
        results = users.collect do |user|
          Hash[ icon: user.image_url(size: icon_size),
                name: user.displayname,
                email: user.email,
                uid: user.uid,
                type: 'user' ]
        end
        render json: { query: params[:query], results: results }
      end
    end
  end

  def toggle_contact
    @contact = _toggle_contact
  end

  def new
    @user = User.new
  end

  def edit
    @user = current_user
  end

  def create # POST /users
    require_terms_of_use or return
    @user = User.new(user_params)
    if @user.save
      flash.success :user_created
      if @user.omniauth_user?
        @user.activate!
        sign_in @user
        redirect_to @user
      else
        @user.send_activation_email
        render 'check_email', layout: 'null' and return
      end
    else
      flash.now.validation :user_validation_error,
        'Dang.',
        'Looks like we had a few glitches:',
        @user
      render :new
    end
  end

  def update # PATCH /users
    require_terms_of_use or return
    @user = current_user
    if @user.update_attributes(user_params)
      flash.now.success :profile_updated, 'Success', 'You updated your profile.'
      redirect_to @user
    else
      flash.validation :user_validation_error,
        'Shoot.',
        'Looks like there were a few problems with your updates:',
        @user
      redirect_to edit_user_path(@user)
    end
  end

  def show
    @user = User.find_by_username(params[:username]) || User.find(params[:id])
  end

  def profile
    @user = current_user
    render 'show'
  end

  # render a confirmation page unless the 'confirm' param is 'true' (which
  # should only be set in the submit button on said confirmation page)
  def destroy
    @user = User.find(params[:id])
    case params['commit']
    when 'cancel'
      redirect_back_or @user
    when 'confirm'
      logger.info "deleting #{@user}"
      logger.info params['reason_for_leaving'] # TODO
      @user.destroy
      flash.now.warning \
        :user_destroyed,
        'Bye bye',
        "You've successfully deleted your account. We're sorry to see you go!"
      redirect_to root_path and return
    else
      render 'confirm_delete' and return
    end
  end

  def check_username
    if User.username_available? params[:username], user: current_user
      render json: { result: :username_available, query: params[:username] }
    else
      render json: { result: :username_taken, query: params[:username] }
    end
  end

  def check_email
    user = User.where( "LOWER(email)=?", params[:email].downcase ).first
    if user.nil? or user == current_user
      result = :email_available
    else
      result = :email_taken
    end
    render json: { result: result, query: params[:email] }
  end

  private

  def user_params
    params.require(:user).permit(*permitted_keys)
  end

  def permitted_keys
    [
      :authenticator,
      :username,
      :forename,
      :surname,
      :middlename,
      :sensitivity,
      :email,
      :title,
      :company,
      :location,
      :description,
      :url_facebook,
      :url_linkedin,
      :url_homepage,
      :url_twitter,
      :url_google_plus,
      :old_password,
      :password,
      :password_confirmation
    ]
  end

  def _toggle_contact
    contact = User.find(params[:contact_id])
    return nil unless signed_in? and not contact.nil?

    case params[:toggle].to_sym
    when :add
      if current_user.has_contact?(contact)
        logger.error('duplicate contact')
      else
        current_user.add_contact(contact)
        flash.now.success :user_contact_created,
          'Contact Added',
          "#{contact.displayname} has been added to your Contacts."
      end
    when :remove
      if current_user.has_contact?(contact)
        current_user.contacts.where(user_id: contact.id).destroy_all
        flash.now.success :user_contact_removed,
          'Contact Removed',
          "#{contact.displayname} has been removed from your Contacts."
      else
        logger.error('invalid contact remove')
      end
    end
    contact
  end

  def record_not_found
    flash.now.error :user_not_found
    @username = params[:username] || params[:id] || 'Wayne Grimball Jr.'
    @error = { title: 'User AWOL', message: '' }
    if params[:username]
      @error[:message] =
        "Sorry, '#{params[:username]}' has left the building.
        Looks like he or she no longer has an account."
    elsif params[:id]
      begin Integer(params[:id]) # check valid integer
        @error[:message] =
          "Sorry, user '#{params[:id]}' has left the building.
          Looks like he or she no longer has an account."
      rescue
        @error = nil
        render 'shared/error', layout: 'null' and return
        # TODO - need better architecture here
      end
    else
      @error[:message] += "Sorry, we couldn't find the droid you are looking for."
    end
    render 'shared/error', layout: 'null' and return
  end

  #########################################################################################
  # void enforce_current_user()
  # Ensure that the user being updated is the one currently signed in.
  # returns: nothing
  # raises: Cluster::UnauthorizedAccessError, if the user tries to update someone else
  #########################################################################################
  def enforce_currrent_user
    unless current_user == User.find(params[:id])
      raise Cluster::UnauthorizedAccessError
    end
  end

  #########################################################################################
  # void cancel()
  # Handle a 'Cancel' button press.
  #########################################################################################
  def cancel
    redirect_to( default_path ) if params[:commit] == 'cancel'
  end

end
