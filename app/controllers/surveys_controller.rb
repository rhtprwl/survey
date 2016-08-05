class SurveysController < ApplicationController
  include ControlFreak
  include Railz
  include Rubix

  helper_method :cloneable?, :postable?

  layout Proc.new {
    ['edit', 'update', 'new'].include?(action_name) ? 'no-sidebar' : 'default'
  }

  before_action :fossick

  def index
    @top_surveys = Survey.top(30)

    filter = SurveyFilter.new(self, params) \
      .first(:s, [:listed, :tlisted, :authored, :favorite]) \
      .include_only(:category)

    # category filter not working. Here is workaround:
    surveys = Survey.viewable_by(current_user)
    if params[:category]
      category_id = Category.find(params[:category]).id
      surveys = surveys.where(category_id: category_id)
    end

    @surveys, @records_count = surveys.search_and_page(params, ids: filter.ids)
    @empty_message, @suggestion = filter.empty_message
    @sign_in_required = filter.sign_in_required?
    @category = params[:category]
    flash.now.info 'no_surveys' if @surveys.empty?
  end

  def show
    @survey = Survey.find(params[:id])
    unless viewable?(@survey)
      flash.error :unauthorized, 'Unauthorized', "You are not allowed to access this survey"
      redirect_to surveys_path
    end
    @show_attach_modal = params[:send]
  end

  def create
  end

  def new
    unless authenticate(
      "You must sign in or #{view_context.link_to("register", signup_path)}
      to create a survey.".html_safe
    ) then return end

    @survey = Survey.draft_survey_for current_user
    render 'edit'
  end

  def edit
    unless authenticate(
        "You must sign in or #{view_context.link_to("register", signup_path)}
        to modify a survey.".html_safe
      ) then return end

    @survey = Survey.find(params[:id])

    # Either 1) user is not the author of this survey, or 2) user has asked to
    # clone this survey rather than edit it. Create a copy and edit that.
    if (not editable?(@survey)) || (cloneable?(@survey) and params[:clone])
      @survey = clone_survey @survey, deprecate: false
      redirect_to edit_survey_path(@survey) and return

    # This survey has been used (sent with a Counsel or Solicitation.) Create a
    # new version and leave the old one lying around -- we'll need it to match
    # tips with their questions.
    elsif @survey.used? # survey has been used
      @survey = clone_survey @survey, deprecate: true
      redirect_to edit_survey_path(@survey) and return

    else # survey is fully editable. Edit it.
    end

    render 'edit'
  end


  def update
    unless authenticate(
      "You must sign in or #{view_context.link_to("register", signup_path)}
      to modify a survey.".html_safe
    )
      render 'edit' and return
    end

    @survey = Survey.find(params[:id])

    update_failed = false
    respond_to do |format|
      format.html do

        case submit

        when :save_and_close, :save_and_send # update and go to survey detail page
          if @survey.update_attributes(survey_params.merge( draft: false ))

            # assume a blank survey is just a mistake; don't try to save, don't
            # report error
            if @survey.blank?
              @survey.destroy
              redirect_back_or surveys_path and return
            end

            redirect_to survey_path(@survey, send: (submit == :save_and_send )) and return
          else
            update_failed = true
          end

        when :update, nil, :add_question # update and stay on current page
          # nil is interpreted the same as :update here because pseudo-element buttons
          # like _destroy or _duplicate do not actually set a submit key. Thus, the
          # default action is just to update the survey.
          # note: this is a pretty questionable design, but might be ok.

          if @survey.update_attributes(survey_params)
            # render 'edit' and return
            redirect_to edit_survey_path(@survey) and return
          else
            update_failed = true
          end
          # TODO - refactor this into get_submit(params)
          # TODO - remove support for :add_question here? (make it js-only)

        when :cancel # abort and return to survey index
          @survey.delete
          flash.notice :survey_cancelled,
            'Survey deleted',
            "You deleted '#{params[:survey][:title]}'."
          redirect_to surveys_path and return

        else # unexpected submit
          handle_error "unexpected submit key #{submit}"
          render 'edit' and return

        end

        if update_failed
          # render error message and stay on edit page
          flash.validation :survey_edit_error,
            'Dang It',
            'There were some problems saving your survey:',
            @survey
          return redirect_back_or edit_survey_path(@survey)
        end
      end

      format.js do
        if @survey.update_attributes(survey_params)
          render json: { status: 'ok' }
        else
          render json: { status: 'error' }
        end
      end
    end
  end

  def toggle_listed
    survey = Survey.find params[:id]
    if current_user.has_listed? survey
      UserListedSurvey.where(
          user_id: current_user.id, survey: survey
        ).destroy_all
      flash.now.success :removed_listed_survey,
        'Removed Survey From Your Listing',
        "You've removed \'#{survey.title}\' from your
          #{help_tag('listed surveys', :listed_surveys)}."
          # #{view_context.link_to 'Undo', toggle_listed_survey_path(survey)}"
    else
    # if (survey_id = params[:add_listed])
      UserListedSurvey.create(user_id: current_user.id, survey: survey)
      flash.now.success :added_listed_survey,
        'Added Survey To Your Listing',
        "You've added \'#{survey.title}\' to your
          #{help_tag('listed surveys', :listed_surveys)}."
          # #{view_context.link_to 'Undo', toggle_listed_survey_path(survey)}"
    end

    # if survey_id
      render 'toggle_listed', locals: {
        survey_id: survey.id, is_added: (not params[:add_listed].nil?)
      }
  end

  def toggle_favorite
    survey = Survey.find params[:id]
    if current_user.has_favorite? survey
      UserFavoriteSurvey.where( user_id: current_user.id, survey: survey).destroy_all
      flash.now.success :removed_favorite_survey,
        'Removed Survey From Your Favorites',
        "You've removed \'#{survey.title}\' from your
          #{help_tag('favorites', :favorite_surveys)}."
          # #{view_context.link_to 'Undo', toggle_favorite_survey_path(survey)}"
    else
      UserFavoriteSurvey.create(user_id: current_user.id, survey: survey)
      flash.now.success :added_favorite_survey,
        'Added Survey To Your Favorites',
        "You've added \'#{survey.title}\' to your
          #{help_tag('favorites', :favorite_surveys)}."
          # #{view_context.link_to 'Undo', toggle_favorite_survey_path(survey)}"
    end

    render 'toggle_favorite', locals: {
      survey_id: survey.id, is_added: (not params[:add_favorite].nil?)
    }
  end

  def post
    @survey = Survey.find params[:id]
    if postable?(@survey)
      post = @survey.create_post
      redirect_to post_path(post)
    else
      flash.now.error :post_error,
        'Post error',
        "You don't have permission to post this survey."
      render 'show'
    end
  end

  def aggregate_user
    return unless authenticate( "You must be signed in to see this page." )
    @survey = Survey.find params[:id]
    @aggregator = @survey.aggregator_for_user current_user
    render 'aggregate'
  end

  private

  def survey_params
    params.require(:survey).permit(
      :private, :category_id, :title, :description,
      # :_destroy,
      # :_new_question,
      #:text_questions_attributes => [:id, :content, :set_position],
      :questions_attributes => [
        :id, :type, :index, :content,
        :new_type, :new_index,
        :_destroy, :_duplicate,
        :_ignore, # for template questions

        # likert fields
        :min, :max, :label_min, :label_mid, :label_max,

        # choices fields
        :choices_attributes => [
          :id, :content,
          :_destroy,
          # :set_position,
        ]
      ],
      :page_breaks_attributes => [
        :id, :title, :description, :index,
        :_destroy, :_duplicate,
        :_ignore, # for template questions
      ]
    )
  end

  def clone_survey old_survey, deprecate: false
    flash.info 'cloned_survey'
    logger.info "SurveysController: cloning survey #{old_survey.id},
      owner: #{old_survey.owner},
      current_user: #{current_user}"
    new_survey = old_survey.deep_clone(temp: true)
    new_survey.owner = current_user
    new_survey.save
    if deprecate
      # not yet implemented
      # old_survey.deprecate new_survey
    end
    new_survey
  end

  class Filter < Object
    # class Filter < ApplicationController - bad idea?
    # TODO - how can I give this class access to all the parent scope?

    def inspect
      { "controller" => @controller.class, "params" => @params, "model" => @model, "ids" => @ids }.to_s
    end

    class << self
      attr_reader :model
    end

    def initialize(controller, params)
      @controller = controller
      @params = params
      @model = self.class.model or throw 'model name not set'
      @ids = nil # default return value
    end

    # TODO - guarantee only one is active?
    def first(params_key, filters)
      filters.each do |filter|
        if @params[params_key].to_s == filter.to_s

          # apply the filter
          @ids = self.send(filter)

          # nil :ids indicates no filter was applied;
          # need to set it to [] to indicate zero results
          @ids ||= []
        end
      end
      return self # for chaining
    end

    def include_only(*filters)
      :TBD
      # e.g., for category
      return self # for chaining
    end

    # this method may return:
    #   nil - indicates that no filtering happened and the collection should return all values
    #   [] - indicates that no results matched the filter
    #   [ids] - a list of ids to be fetched
    def ids
      # TODO - access the flash
      # flash.now.info "no_#{@model.symbolize}".to_sym if (@ids and @ids.empty?)
      @ids
    end

    def empty_message
      if @params[:query]
        ["Sorry, we couldn't find any surveys matching '#{@params[:query]}'#{@qualifier}.",
         nil]
      elsif not signed_in?
        "You must be signed in to use this feature. #{view_context.link_to 'Sign in', sign_in_path}".html_safe
      elsif @actor and @action
        ["Looks like #{@actor} #{@actor == 'you' ? 'haven\'t' : 'hasn\'t'} #{@action} any surveys yet#{@help}#{@qualifier}.".html_safe,
        @suggestion.html_safe]
      else
        ["Oops, we couldn't find any surveys.",
         "Please try again later."]
      end
    end

    def method_missing(method, *args, &block)
      @controller.send method, *args, &block
    end
  end

  class SurveyFilter < Filter
    @model = Survey

    def authored
      @sign_in_required = true
      ids = current_user.authored_surveys.map &:id if signed_in?
      if ids.nil? or ids.empty?
        @actor, @action = "you", "written"
        @suggestion = view_context.link_to "Create one now", new_survey_path
      end
      ids
    end

    def favorite
      @sign_in_required = true
      ids = current_user.favorite_surveys.map &:id if signed_in?
      if ids.nil? or ids.empty?
        @actor, @action = "you", help_tag('favorited', :favorite_survey)
        @suggestion = view_context.link_to 'Favorite one now!', surveys_path
      end
      ids
    end

    def listed
      @sign_in_required = true
      ids = current_user.listed_surveys.map &:id if signed_in?
      if ids.nil? or ids.empty?
        @actor, @action = "you", help_tag('listed', :listed_survey)
        @suggestion = view_context.link_to 'List one now!', surveys_path
      end
      ids
    end

    def tlisted
      @sign_in_required = false
      ids = target_user.listed_surveys.map &:id if target_user?
      if ids.nil? or ids.empty?
        @actor, @action = target_user.displayname, help_tag('listed', :listed_survey)
      end
      ids
    end

    def sign_in_required?
      @sign_in_required
    end

  end

  def record_not_found
    binding.pry
    flash.now.error :survey_not_found
    @message = "Sorry, we couldn't find that survey -- did the author delete it? No? Dang. Let's just blame this on cosmic rays then. \
                    (We should really radiation-harden our servers one of these days.)"
    render 'shared/error', layout: 'null' and return
  end

  #########################################################################################
  # boolean viewable?( survey )
  # Can this survey be viewed by the current user(or visitor)?
  # Everyone can view the survey if it's public but only that who can edit
  # a private survey can view it.
  # returns: boolean
  #########################################################################################
  def viewable? survey
    !survey.private or editable? survey
  end

  #########################################################################################
  # boolean editable?( survey )
  # Can this survey be edited by the current user? The user must own the survey and it
  # must not have any replies to it (if so, a new copy must be created).
  # TODO: Need to revisit this in the view. The user may be confused at being unable to
  # edit his or her own survey.
  # returns: boolean
  #########################################################################################
  # def editable? survey
  #   signed_in? and current_user.owns?(survey)
  # end

  #########################################################################################
  # boolean cloneable?( survey )
  # Can this survey be cloned and edited by the current user? If the user is signed in,
  # then yes.
  # returns: boolean
  #########################################################################################
  def cloneable? survey
    signed_in?
  end

  #########################################################################################
  # boolean postable?( survey )
  # Can this survey be posted by the current user? If it's editable and not already
  # posted, then yes. (Actually, we probably don't care if it's editable or not, but for
  # now let's be safe.)
  # returns: boolean
  #########################################################################################
  def postable? survey
    editable?(survey) and not survey.posted? and not survey.private?
  end

end
