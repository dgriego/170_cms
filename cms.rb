# application.rb

require 'sinatra'
require 'sinatra/reloader' if development?
require 'tilt/erubis'
require 'pry'

root = File.expand_path("..", __FILE__)

get '/' do
  # data = Dir.open('data/')
  # @files = data.select { |file| file if File.extname(file) == '.txt' }

  @files = Dir.glob(root + "/data/*").map do |path|
    File.basename(path)
  end

  erb :documents_list
end

get '/:filename' do
  content_type 'text/plain'
  file_path = "#{root}/data/#{params[:filename]}"
  File.read(file_path)
end
