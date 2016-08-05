class SurveyQuestion < ActiveRecord::Base
  include SuperModel
  include DeepClone
  include HTMLFriendly

  DEFAULT_CONTENT = 'Untitled Question'

  self.abstract_class = true

  belongs_to :survey
  validates_presence_of :survey_id
  validates_associated :survey
  validates :index, numericality: { greater_than_or_equal_to: 1 }, allow_nil: true

  has_many :tips #, :dependent => destroy

  handles :_ignore

  compares_equality_on :survey_id, :content

  def self.subclasses
    [TextQuestion, MultipleChoiceQuestion, LikertQuestion]
  end

  def type
    SurveyQuestion::Type.new(self)
  end

  after_create :set_initial_index

  # kludge to allow sorting by index with nil
  def sort_index
    self.index || 0
  end

  def blank?
    return true unless self.content.present?
    return true if self.content == DEFAULT_CONTENT
    return false
  end

  def set_initial_index
    if self.survey
      # survey.questions.count includes self
      self.index = self.survey.questions.count
    else
      self.index = 1
    end
    save
  end

  class << self

    def find id, type: nil
      case type
      when nil
        # subclass find (e.g., TextQuestion.find(1)
        return super(id)
      when String
        return class_for(type).find_by_id(id)
      when Fixnum
        return SurveyQuestion::Type.find(type).find_by_id(id)
      end
    end

    # factory method for returning subclass instances
    def class_for(type)
      klass = type.to_s.classify.constantize rescue nil
      return klass if self.subclasses.include? klass
    end

    # DELETEME
    # def make(type, survey: nil, **attributes)
    #   class_for(type).new(survey: survey, **attributes)
    # end

    def type
      SurveyQuestion::Type.new(self)
    end

  end

  class Type

    # Somehat overkilled castable question type.
    # It turns out sometimes we want type as a string and sometimes
    # as an int; this way it can do both ways.

    def initialize question_or_type

      case question_or_type
      when Class
        @symbol = question_or_type.symbolize
        question_class = question_or_type
      when SurveyQuestion
        @symbol = question_or_type.class.symbolize
        question_class = question_or_type.class
      when Symbol, String
        @symbol = question_or_type.to_sym
        question_class = question_or_type.to_s.classify.constantize
      end
      @index = SurveyQuestion.subclasses.index(question_class)
    end

    def to_sym
      @symbol
    end

    def to_str
      @symbol.to_s
    end
    alias :to_s :to_str

    def to_int
      @index
    end
    alias :to_i :to_int

    def self.find(index)
      SurveyQuestion.subclasses[index]
    end

    def self.[]=(type)
    end

    def ==(other)
      case other
      when Symbol
        self.to_sym == other
      when Integer
        self.to_int == other
      when String
        self.to_s == other
      else
        false
      end
    end
  end

end
