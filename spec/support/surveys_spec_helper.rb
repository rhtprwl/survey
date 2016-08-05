def unique_query_for(survey)
  survey.title.split.first(5).join(" ")
end

def select_new_random_category
  current_category_id = page.find('#survey_category_id').value.to_i
  new_category_name = Category[(current_category_id + 1) % Category.count].name
  select(new_category_name, from: 'survey_category_id')
  new_category_name
end

def have_consistent_query_results_message(page_num: 1, total: nil)

  # total is total records matching query; this may not equal Survey.count
  total ||= Survey.count

  num_surveys_on_page = page.all('#surveys-index li.survey').count

  case num_surveys_on_page
  when 0
    return have_css '#query-results', text: /no results found/i
  when 1
    if total == 1
      return have_css '#query-results', text: /showing 1 of 1 survey/i
    end
  end

  bottom = (page_num - 1) * Survey::PER_PAGE + 1
  top = bottom + num_surveys_on_page - 1
  have_css '#query-results', text: /showing #{bottom}-#{top} of #{total} surveys/i
end

def verify_question_indices
  page.all('ul.items-fields > li.question:not([class~="deleted"])').each_with_index do |question_li, index|
    index_field = question_li.first('.index input')
    expect(index_field[:value].to_i).to eq(index + 1)
  end
end

def save_survey
  if javascript_enabled?
    expect(page).to complete_ajax_save
  else
    click_on :update, match: :first
  end
end

def update_survey
  click_on :update, match: :first
end

def save_and_close_survey
  click_on :save_and_close, match: :first
end

def current_survey
  Survey.find_by_id page.first('.survey-fields')['data-id']
end
alias current_survey_model current_survey

def questions
  page.all('ul.items li.question')
end

def verify(thing = nil, question: nil, **attributes)
  if thing == :survey
    attributes.each do |field, value|
      case (field[/has_(.*)/, 1] || field)
      when :title, :description
        expect(find_field("survey_#{field.to_s}").value).to eq(value)
      when :category
        expect(page).to have_select('survey_category_id', selected: value)
      end
    end
  # elsif question
  #   attributes.each do |field, value|
      # expect(find_field("survey_questions_attributes_#{question}_#{field}")).to eq(value)
    # end
  end
end

def verify_presence_of(survey: nil, question: nil)
  if survey
    expect(page).to have_css('.survey-summaries', text: survey.description.first(40))
  elsif question
    expect(page).to have_content(question.description)
  end
end

def verify_absence_of(survey: nil, question: nil)
  if survey
    expect(page).not_to have_css('.survey-summaries', text: survey.description.first(40))
  elsif question
    # expect(page).not_to have_css("li.questions##{question.uid}")
    expect(page).not_to have_css("li.question", text: question.content)
  end
end

# verify cloned models
def equal_surveys? first, second
  [:title, :description, :instructions].each do |attr|
    return false unless first.send(attr) == second.send(attr)
  end
  (first.questions.zip second.questions).each do |q1, q2|
    return false unless equal_questions? q1, q2
  end
  return true
end

def equal_questions? first, second
  return false unless first.content == second.content
  return false unless first.index == second.index
  return false unless first.class == second.class

  case first.class
  when LikertQuestion
    [:label_min, :label_mid, :label_max, :min, :max].each do |attr|
      return false unless first.send(attr) == second.send(attr)
    end
  when MultipleChoiceQuestion
    return false unless first.choices.count == second.choices.count
    (first.choices.zip second.choices).each do |c1, c2|
      return false unless equal_choice? c1, c2
    end
  else
    # no more attributes
  end
  return true
end

def equal_choice? first, second
  return false unless first.content == second.content
  return false unless first.index == second.index
  return true
end

# verify clone in the view
def verify_survey_is_clone_of(original_survey)
  expect(Rails.application.routes.recognize_path(current_path)[:id]).not_to eq(original_survey.id)
  expect(page).to have_flag('.info#cloned_survey')

  expect(page).to have_field('survey_title', with: original_survey.title)
  expect(page).to have_field('survey_description', with: original_survey.description)

  expect(page).to have_css(".items-fields > li.question", count: original_survey.questions.count)
  original_survey.questions.each do |question|
    expect(page).to have_content_or_input(question.content)
  end
end

def verify_no_surveys(context, content = nil)
  expect(page).to have_flag '.info#no_surveys'
  expect(page).to have_content(/no results found/i)
  empty_message = case context
  when :listed
    "like you haven't listed any surveys yet."
  when :tlisted
    "like #{content} hasn't listed any surveys yet."
  when :favorite
    "like you haven't favorited any surveys yet."
  when :query
    "Sorry, we couldn't find any surveys matching '#{content}'."
  when :authored
    "Looks like you haven't written any surveys yet."
  end
  expect(page).to have_content(/#{empty_message}/i)
end

def select_new_random_type_for(question)
  question_types = SurveyQuestion.subclasses.map(&:symbolize)
  old_type = question.find(".type input", visible: false).value
  new_type = (question_types - [old_type.to_sym]).sample.to_s
  question.find(".type select option[value='#{new_type}']").select_option
  return new_type
end

def set_question_types
  indices = (0 .. (page.all('ul.items-fields li.question').count - 1)).to_a.cover
  new_types = {}
  content = {}
  old_questions = {}

  indices.each do |index|
    old_question = @survey.questions[index]
    old_questions[index] = old_question
    current_type = questions[index].find(".type input", visible: false).value
    expect(old_question.type.to_s).to eq(current_type.to_s)

    content[index] = page.find("#survey_questions_attributes_#{index}_content").value
    new_types[index] = select_new_random_type_for questions[index]

    # puts "**** #{@survey.questions[index].uid}[index #{index}] ==> #{new_type}"
  end

  [indices, new_types, content, old_questions]
end
