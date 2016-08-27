require 'slack-ruby-client'
require_relative 'slack-ruby-bot/slack-ruby-bot'
require_relative 'applicant_status_update.rb'
require_relative 'judge_request_manager.rb'
require_relative 'judge_session_validator.rb'
require_relative 'judge_participant_handler.rb'
require_relative 'judge_leaderboard_handler.rb'

class JudgeBot < SlackRubyBot::Bot

  Slack.configure do |config|
    config.token = ENV['SLACK_API_TOKEN']
  end

  # constants
  @slack = Slack::Web::Client.new
  @request_manager = JudgeRequestManager.new
  @sucess = 'success'
  @default_message_color = '#36a64f'
  @no_resume = 'No resume'
  @no_github = 'No github'
  @bot_types = ['applicant', 'project']
  @choice_a = 'CHOICE_A'
  @choice_b = 'CHOICE_B'

  # judging session variables
  @judging_status = false
  @bot_season = 'season'
  @bot_event = 'event'
  @bot_type = 'applicant'
  @bot_year = 9999

  help do
    title 'Judging Bot'
    desc 'Performs pairwise judging on applicants and projects.'

    command 'start judging session <season> <event> <year> <type>' do
      desc 'This starts a judging session with the specified season, event, year, and type'
    end

    command 'stop judging session' do 
      desc 'This stops the currently active judging session if available'
    end

    command 'judge' do
      desc 'Retrieves a pair of entries for the user to judge.'
    end

    command 'select <first/second>' do
      desc 'Selects the first or second entry in a pairwise comparison'
    end

    command 'leaderboard' do
      desc 'Shows a leaderboard for the judges'
    end

    command 'update applicant status <accept number> <waitlist number>' do
      desc 'Updates accepted, waitlisted, and rejected participants based on given numbers (applicant-specific)'
    end

    command 'applicant <ID>' do
      desc 'Displays information about the specified applicant (applicant-specific)'
    end
  end

  command 'judge' do |client, data, match|
    judge_command(client, data, match)
  end

  match /^start judging session (?<season>\w*) (?<event>\w*) (?<year>\d{4}*) (?<type>\w*)$/ do |client, data, match|
    if @judging_status
      client.say(text: 'An active ' + @bot_type + ' judging session for ' + @bot_event + ' ' + 
                 @bot_season + ' ' + @bot_year.to_s + ' is already active!' , channel: data.channel)
      return
    end
    @bot_season = "#{match[:season]}".to_s
    @bot_event = "#{match[:event]}".to_s
    @bot_year = "#{match[:year]}".to_i
    @bot_type = "#{match[:type]}".to_s
    valid_season = validate_season(@bot_season, client, data)
    valid_event = validate_event(@bot_event, client, data)
    valid_year = validate_year(@bot_year, client, data)
    valid_type =  validate_type(@bot_type, client, data)
    return unless valid_season && valid_event && valid_year && valid_type
    session_name = @bot_season + @bot_event + @bot_year.to_s + @bot_type
    error = @request_manager.start_judging_session(participants_for_event.length, session_name)
    if error == ''
      @judging_status = true
      client.say(text: 'An active ' + @bot_type + ' judging session for ' + @bot_event + ' ' + 
                 @bot_season + ' ' + @bot_year.to_s + ' has begun!' , channel: data.channel)
    else
      client.say(text: error, channel: data.channel)
    end
  end

  command 'stop judging session' do |client, data, match|
    return unless active_judging_session(client, data)
    @judging_status = false
     client.say(text: 'The active ' + @bot_type + ' judging session for ' + @bot_event + ' ' + 
               @bot_season + ' ' + @bot_year.to_s + ' has been stopped' , channel: data.channel)
  end

  match /^select (?<firstsecond>\w*)$/ do |client, data, match|
    result = "#{match[:firstsecond]}".to_s
    if result != 'first' && result != 'second'
      client.say(text: 'You must select the first or second!', channel: data.channel)
    else
      if result == 'first'
        favored = @choice_a
      else
        favored = @choice_b
      end
      error = @request_manager.perform_judge_decision(data.user, favored)
      if error == '' 
        client.say(text: 'Successfully performed judge decision, please choose again!', channel: data.channel)
        judge_command(client, data, match)
      else
        client.say(text: error, channel: data.channel)
      end
    end
  end

  match /^update applicant status (?<accept_num>\d*) (?<waitlist_num>\d*)$/ do |client, data, match|
    return unless active_judging_session(client, data)
    accept_num = "#{match[:accept_num]}".to_i
    waitlist_num = "#{match[:waitlist_num]}".to_i
    body = @request_manager.get_results
    if body['error'].to_s == ''
      results = body['votes'].keys
      update_participant_statuses(participants_for_event, accept_num, waitlist_num, results, 
                                  @bot_season, @bot_event, @bot_year)
      client.say(text: 'Participant statuses updated!', channel: data.channel)
    else 
      client.say(text: body['error'], channel: data.channel)
    end
  end

  match /^applicant (?<id>\w*)/ do |client, data, match|
    return unless active_judging_session(client, data)
    id = "#{match[:id]}".to_i
    output = output_for_participant(id, data, false)
    if output == @success
       p = Participant.find(id)
       client.web_client.chat_postMessage(
        channel: data.channel,
        as_user: true,
        attachments: [
          {
            pretext: 'Information for applicant ' + p.id.to_s,
            fields: fields_for_applicant(p),
            color: @default_message_color
          }
        ]
      )
    else
      client.say(text: output, channel: data.channel)
    end
  end

  command 'leaderboard' do |client, data, match|
    body = @request_manager.get_results
    if body['error'].to_s == ''
      judge_counts = body['judge_counts']
      if judge_counts.length == 0
        client.say(text: "No entries have been judged!", channel: data.channel) 
      else
        client.web_client.chat_postMessage(
          channel: data.channel,
          as_user: true,
          attachments: [
            {
              title: "Current Leaderboard",
              fields: fields_for_leaderboard(body['judge_counts']),
              color: @default_message_color
            }
          ]
        )
      end
    else
      client.say(text: body['error'], channel: data.channel)
    end
  end

end

def judge_command(client, data, match)
  return unless active_judging_session(client, data)
  result = @request_manager.get_judge_decision(data.user)
  if result.length == 1 
    client.say(text: result[0], channel: data.channel)
  end
  participants = all_participant_ids_for_event
  participant_one = Participant.find(participants[result[0]])
  participant_two = Participant.find(participants[result[1]])
  post_participants_message(client, data, participant_one, participant_two, @default_message_color)
end
  
