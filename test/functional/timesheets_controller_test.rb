require File.dirname(__FILE__) + '/../test_helper'
class ActiveSupport::TestCase
  def self.use_timesheet_controller_shared(&block)
    should 'should set @timesheet.allowed_projects to the list of current projects the user is a member of' do
      Member.destroy_all # clear any setup memberships

      project1 = Project.generate!
      project2 = Project.generate!
      projects = [project1, project2]

      projects.each do |project|
        Member.generate!(:principal => @current_user, :project => project, :roles => [@normal_role])
      end
      
      instance_eval &block

      assert_equal projects, assigns['timesheet'].allowed_projects
    end

    should 'include public projects in @timesheet.allowed_projects' do
      project1 = Project.generate!(:is_public => true)
      project2 = Project.generate!(:is_public => true)
      projects = [project1, project2]

      instance_eval &block

      assert_contains assigns['timesheet'].allowed_projects, project1
      assert_contains assigns['timesheet'].allowed_projects, project2
    end

    should 'should set @timesheet.allowed_projects to all the projects if the user is an admin' do
      Member.destroy_all # clear any setup memberships

      @current_user.admin = true
      project1, _ = *generate_project_membership(@current_user)
      project2, _ = *generate_project_membership(@current_user)
      projects = [project1, project2]

      instance_eval &block

      assert_equal projects, assigns['timesheet'].allowed_projects
    end

    should 'should get the list size from the settings' do
      settings = { 'list_size' => 10, 'precision' => '2' }
      Setting.plugin_timesheet_plugin = settings
      
      instance_eval &block
      assert_equal 10, assigns['list_size']
    end

    should 'should get the precision from the settings' do
      settings = { 'list_size' => 10, 'precision' => '2' }
      Setting.plugin_timesheet_plugin = settings
      
      instance_eval &block
      assert_equal 2, assigns['precision']
    end

    should 'should create a new @timesheet' do
      instance_eval &block
      assert assigns['timesheet']
    end
  end
end


class TimesheetsControllerTest < ActionController::TestCase
  def generate_and_login_user(options = {})
    @current_user = User.generate_with_protected!(:admin => false)
    @request.session[:user_id] = @current_user.id
  end

  def generate_project_membership(user)
    @project = Project.generate!(:is_public => false)
    @member = Member.generate!(:principal => user, :project => @project, :roles => [@normal_role])
    [@project, @member]
  end

  def setup
    @normal_role = Role.generate!(:name => 'Normal User', :permissions => [:view_time_entries])
  end

  context "#index with GET request" do
    setup do
      generate_and_login_user
      generate_project_membership(@current_user)
      get 'index'
    end

    use_timesheet_controller_shared do
      get 'index'
    end
    
    should_render_template :index
    
    should 'have no timelog entries' do
      assert assigns['timesheet'].time_entries.empty?
    end
  end

  context "#index with GET request and a session" do
  
    should 'should read the session data' do
      generate_and_login_user
      @current_user.admin = true
      @current_user.save!

      projects = []
      4.times do |i|
        projects << Project.generate!
      end
      
      session[TimesheetsController::SessionKey] = HashWithIndifferentAccess.new(
                                                                               :projects => projects.collect(&:id).collect(&:to_s),
                                                                               :date_to => '2009-01-01',
                                                                               :date_from => '2009-01-01'
                                                                               )

      get :index
      assert_equal '2009-01-01', assigns['timesheet'].date_from.to_s
      assert_equal '2009-01-01', assigns['timesheet'].date_to.to_s
      assert_equal projects, assigns['timesheet'].projects
    end
  end

  context "#index with GET request from an Anonymous user" do
     setup do
      get 'index'
    end

    should_render_template :no_projects

  end

  context "#create with POST request without saving" do
    setup do
      generate_and_login_user
    end

    use_timesheet_controller_shared do
      post :create, 'query-only' => true, :timesheet => {}
    end
    
    should 'should only allow the allowed projects into @timesheet.projects' do
      project1 = Project.generate!(:is_public => false)
      project2 = Project.generate!(:is_public => false)
      projects = [project1, project2]

      Member.generate!(:principal => @current_user, :project => project1, :roles => [@normal_role])

      post :create, 'query-only' => true, :timesheet => { :projects => [project1.id.to_s, project2.id.to_s] }

      assert_equal [project1], assigns['timesheet'].projects
    end

    should 'include public projects' do
      project1 = Project.generate!(:is_public => true)
      project2 = Project.generate!(:is_public => true)
      projects = [project1, project2]

      post :create, 'query-only' => true, :timesheet => { :projects => [project1.id.to_s, project2.id.to_s] }

      assert_contains assigns['timesheet'].allowed_projects, project1
      assert_contains assigns['timesheet'].allowed_projects, project2
    end

    should 'should save the session data' do
      generate_project_membership(@current_user)
      post :create, 'query-only' => true, :timesheet => { :projects => ['1'] }

      assert @request.session[TimesheetsController::SessionKey]
      assert @request.session[TimesheetsController::SessionKey].keys.include?('projects')
      assert_equal ['1'], @request.session[TimesheetsController::SessionKey]['projects']
    end

    context ":csv format" do
      setup do
        generate_project_membership(@current_user)
        post :create, 'query-only' => true, :timesheet => {:projects => ['1']}, :format => 'csv'
      end

      should_respond_with_content_type 'text/csv'
      should_respond_with :success
    end
  end

  context "DELETE to :reset" do
    setup do
      generate_and_login_user
      @current_user.admin = true
      @current_user.save!

      @project = Project.generate!
      session[TimesheetsController::SessionKey] = HashWithIndifferentAccess.new(
                                                                               :projects => [@project.id.to_s],
                                                                               :date_to => '2009-01-01',
                                                                               :date_from => '2009-01-01'
                                                                               )

      delete :reset
    end
    
    should_respond_with :redirect
    should_redirect_to('index') {{:action => 'index'}}
    should 'clear the session' do
      assert session[TimesheetsController::SessionKey].blank?
    end

  end
end
