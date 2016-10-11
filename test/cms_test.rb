ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/reporters'
require 'rack/test'
require 'fileutils'
require 'pry'
Minitest::Reporters.use!

require_relative '../cms'

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = '')
    File.open(File.join(data_path, name), 'w') do |file|
      file.write(content)
    end
  end

  def app
    Sinatra::Application
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { 'rack.session' => { username: 'admin' } }
  end

  def test_index
    create_document 'about.md'
    create_document 'history.txt'

    get '/'

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'about.md'
    assert_includes last_response.body, 'history.txt'
  end

  def test_viewing_document_contents
    create_document 'history.txt', '1993 - Yukihiro Matsumoto'

    get '/history.txt'
    assert_equal 200, last_response.status
    assert_equal 'text/plain;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, '1993 - Yukihiro Matsumoto'
  end

  def test_viewing_markdown_documents
    create_document 'about.md', 'Processing Markdown'

    get '/about.md'
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Processing Markdown'
  end

  def test_viewing_non_existent_document
    get '/foobar.txt'
    assert_equal 302, last_response.status
    assert_equal session[:error], 'foobar.txt does not exist.'
  end

  def test_editing_a_file
    create_document 'changes.txt'

    get '/changes.txt/edit', {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'textarea'
  end

  def test_updating_a_file
    create_document 'changes.txt'

    post '/changes.txt', { file_content: 'test' }, admin_session
    assert_equal 302, last_response.status
    assert_equal session[:success], 'changes.txt has been updated.'

    get '/changes.txt'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'test'
  end

  def test_view_template
    get '/file/new', {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<input type="text" name="file">'
  end

  def test_creating_new_file
    post '/file/new', { file: 'test.txt' }, admin_session
    assert_equal 302, last_response.status
    assert_equal session[:success], 'test.txt has been created.'

    get '/'
    assert_includes last_response.body, 'test.txt'
  end

  def test_create_new_document_without_filename
    post '/file/new', { file: '' }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'A name is required'
  end

  def test_deleting_file
    create_document 'remove.txt'
    post '/file/delete', { file: 'remove.txt' }, admin_session
    assert_equal 302, last_response.status
    assert_equal session[:success], 'remove.txt was deleted succesfully'

    get '/'
    refute_includes last_response.body, 'test.txt'
  end

  def test_signin_template
    get '/user/signin'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Username'
    assert_includes last_response.body, 'Password'
  end

  def test_successful_sigin
    post '/user/signin', username: 'admin', password: 'secret'
    assert_equal 302, last_response.status
    assert_equal session[:success], 'Welcome admin!'
  end

  def test_unsuccessful_signin
    post '/user/signin', username: 'foo', password: 'bar'
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Invalid Credentials.'
  end

  def test_sign_out
    get '/', {}, { 'rack.session' => { username: 'admin' } }
    post '/user/signout', username: 'admin'
    assert_equal 302, last_response.status
    assert_equal session[:success], 'You have been signed out.'
  end
end