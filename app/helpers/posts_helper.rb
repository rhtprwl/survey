module PostsHelper
  include MailboxesHelper

  #########################################################################################
  # boolean editable?( question )
  # Can this CrowdQuestion be edited by the current user? For now, yes iff the user owns
  # the question. In the future this may be more complicated, involving reputation,
  # whether the question has already been answered, etc..
  # returns: boolean
  #########################################################################################
  # def editable? question
  #   signed_in? and question.author == current_user
  # end

  #########################################################################################
  # String upvoted_message_for( response )
  # Return a message for the current user about the last (only) time they upvoted this
  # response.
  # returns: String
  #########################################################################################
  def upvoted_message_for response
    return nil unless response.upvoted_by? current_user
    <<-eos.strip_heredoc
     You upvoted this response
     #{friendly_when response.upvote_by( current_user ).voted_at}.
    eos
  end

  #########################################################################################
  # String downvoted_message_for( response )
  # Return a message for the current user about the last (only) time they downvoted this
  # response.
  # returns: String
  #########################################################################################
  def downvoted_message_for response
    return nil unless response.downvoted_by? current_user
    <<-eos.strip_heredoc
     You downvoted this response
     #{friendly_when response.downvote_by( current_user ).voted_at}.
    eos
  end

  #########################################################################################
  # String voted_message_for( response )
  # Return either the upvoted or downvoted message, depending on what the user did most
  # recently.
  # returns: String
  #########################################################################################
  def voted_message_for response
    return nil unless response.voted_on_by? current_user
    last_vote = ResponseVote.by(current_user).on(response).last
    if last_vote.is_a? ResponseUpvote
      upvoted_message_for response
    else
      downvoted_message_for response
    end
  end

end
