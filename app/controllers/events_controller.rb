class EventsController < ApplicationController
  include EventsUtil
  include MailchimpUtil

  def index
    render json: Event.all
  end

  def show
    @event = Event.find(params[:id])
  end

  def create_school_list
    semester = Semester.where('season = ? AND year = ?', Semester.seasons[params[:season]], params[:year]).first
    event = semester.events.where('event_type = ?', Event.event_types[params[:event_type]]).first
    params[:school]
    render json: "Hi"
  end

  # creates a new event and makes a new mailchimp list for that event
  def create
    @event = Event.new(event_params)
    make_mailchimp_list(params[:from_name], params[:from_email], @event)
    add_form_info(params[:form_id], @event)
    redirect_to :back
  end

  def semester
    @semester = Semester.where('season = ? AND year = ?', Semester.seasons[params[:season]], params[:year]).first
    render json: @semester.events.map{|event| {:form_ids => event.form_ids, :form_names => event.form_names, 
                                        :form_routes => event.form_routes, :mailchimp_ids => event.mailchimp_ids, 
                                        :event_type => event.event_type, :season => event.semester.season, 
                                        :year => event.semester.year}}
  end

  def current
    events = Event.event_types.map{|type| Event.where(event_type: type).order('created_at DESC').first}
    render json: events.compact!.map{|event| {:form_ids => event.form_ids, :form_names => event.form_names, 
                                        :form_routes => event.form_routes, :mailchimp_ids => event.mailchimp_ids, 
                                        :event_type => event.event_type, :season => event.semester.season, 
                                        :year => event.semester.year}}
  end

  def mailchimp
    HackDukeAPI::Application.load_tasks
    Rake::Task['resque:mailchimp'].invoke
    render json: {:action => 'Mailchimp synchronization performed'}
  end

  def destroy
    @event = Event.find(params[:id])
    delete_mailchimp_lists(@event)
    @event.destroy!
    redirect_to :back
  end

  def update
    @event = Event.find(params[:id])
    add_form_info(params[:added_form_id], @event)
    redirect_to :back
  end

  def event_params
    params.require(:event).permit(:event_type, :semester_id, :form_ids => [], :mailchimp_ids => [])
  end
  
end
