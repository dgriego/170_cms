# application.rb

require 'sinatra'
require 'sinatra/reloader' if development?
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'
require 'fileutils'
require 'pry'

VALID_FILE_TYPES = %w(.txt .md)

configure do
  enable :sessions
  set :session_secret, 'super secret'
end

def render_markdown(md)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(md)
end

def load_file_content(file_path)
  content = File.read(file_path)
  case File.extname(file_path)
  when '.md'
    erb render_markdown(content)
  when '.txt'
    content_type 'text/plain'
    content
  end
end

def file_path(file)
  File.join(data_path, file)
end

def non_file_error_message(file)
  "#{file} does not exist."
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def user_signed_in?
  session.key?(:username)
end

def require_signed_in_user
  unless user_signed_in?
    session[:error] = "You must be signed in to do that."
    redirect "/"
  end
end

def yml_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
end

def load_user_credentials
  credentials_path = yml_path
  YAML.load_file(credentials_path)
end

def valid_user?(username, password)
  credentials = load_user_credentials
  # check if user exists and if the password match password entered
  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

def has_supported_file_ext?(file)
  VALID_FILE_TYPES.any? { |ext| File.extname(file) == ext }
end

def file_count_by_name(file)
  # this will include copied files,
  # not sure if this makes sense to do it this way
  Dir.glob("#{data_path}/#{file}*").count
end

# will return new file name ext something.txt => something2.txt
def copied_file_name(file)
  # if the filename contains _copy and any numbers we remove those
  # to get an accurate count of the original file
  clean_file_name = file.sub(/_copy\d*/, '')
  filename = clean_file_name.split('.').first
  ext = clean_file_name.split('.').last
  count = file_count_by_name(filename)
  "#{filename}_copy#{count}.#{ext}"
end

get '/' do
  # my original implementation loops through the directories files and
  # then selects only the files with the txt ext.
  # using Dir.glob uses a similar approach but only returns 'visible' files
  # data = Dir.open('data/')
  # @files = data.select { |file| file if File.extname(file) == '.txt' }

  @files = Dir.glob("#{data_path}/*").map do |path|
    File.basename(path)
  end

  erb :index
end

get '/file/new' do
  require_signed_in_user

  erb :new
end

get '/image/new' do
  require_signed_in_user

  erb :new_image
end

post '/image/new' do
  filepath = "#{data_path}/#{params[:image][:filename]}"
  temp_filepath = params[:image][:tempfile].path
  FileUtils.cp(temp_filepath, filepath)

  session[:success] = 'Image upload successful.'
  redirect '/'
end

# view the files contents
get '/:file' do
  file_path = file_path(params[:file])

  # I originally implemented the use of File.exist? because
  # I thought checking the name of the file was sufficient
  # if File.exist? file_path
  # Here I'm going to use what was used in the solution because
  # it checks that the name exists but also that it is indeed a
  # 'regular' file
  if File.file?(file_path)
    load_file_content(file_path)
  else
    session[:error] = non_file_error_message(params[:file])
    redirect '/'
  end
end

# edit a files contents
get '/:file/edit' do
  require_signed_in_user

  # do I want a method that will set the session message and
  # validate if a user is signed in?
  @file = params[:file]
  file_path = file_path(@file)

  if File.file?(file_path)
    @file_content = File.read(file_path)
    erb :edit
  else
    session[:error] = non_file_error_message(params[:file])
    redirect '/'
  end
end

get '/user/signin' do
  erb :signin
end

get '/user/signup' do
  erb :signup
end

post '/user/signup' do
  users = YAML.load_file(yml_path)
  bcrypt_password = BCrypt::Password.create(params[:password])
  users[params[:username]] = bcrypt_password.to_s
  File.open(yml_path, 'w') { |f| YAML.dump(users, f) }

  session[:success] = 'Account creation successful, you can now sign in.'

  redirect '/user/signin'
end

# ----- POST -------
# editing a file
post '/:file' do
  require_signed_in_user

  file_path = file_path(params[:file])

  if File.file?(file_path)
    File.write(file_path, params[:file_content])
    session[:success] = "#{params[:file]} has been updated."
    redirect '/'
  else
    session[:error] = non_file_error_message(params[:file])
    redirect "/#{params[:file]}"
  end
end

# creating a new file
post '/file/new' do
  require_signed_in_user

  file = params[:file].to_s

  if file.size == 0
    session[:error] = 'A name is required.'
    status 422
    erb :new
  elsif !has_supported_file_ext?(file)
    session[:error] = 'File must have a .txt or .md extension.'
    status 422
    erb :new
  else
    file_path = File.join(data_path, file)

    File.write(file_path, '')
    session[:success] = "#{params[:file]} has been created."

    redirect '/'
  end
end

# copying a file
post '/file/copy' do
  require_signed_in_user

  original_file_path = file_path(params[:file])
  new_file = copied_file_name(params[:file])
  new_file_path = file_path(new_file)

  FileUtils.cp(original_file_path, new_file_path)

  session[:success] = "#{params[:file]} has been copied."

  redirect '/'
end

# deleting a file
post '/file/delete' do
  require_signed_in_user

  file_path = file_path(params[:file])

  if File.file?(file_path)
    File.delete(file_path)
    session[:success] = "#{params[:file]} was deleted succesfully"
    redirect '/'
  else
    session[:error] = "#{params[:file]} does not exist."
    redirect '/'
  end
end

post '/user/signin' do
  username = params[:username]
  password = params[:password]

  if valid_user?(username, password)
    session[:username] = username
    session[:success] = "Welcome #{username}!"
    redirect '/'
  else
    status 422
    session[:error] = "Invalid Credentials."
    erb :signin
  end
end

post '/user/signout' do
  session.delete(:username)
  session[:success] = 'You have been signed out.'
  redirect '/'
end