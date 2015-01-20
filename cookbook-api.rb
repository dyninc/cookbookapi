#!/usr/bin/env ruby

########## Configuration block
CHEF_SERVER_URL = 'https://localhost'
CHEF_CLIENT_NAME = 'cookbook-api'
CHEF_CLIENT_KEY = './client.pem'

COOKBOOK_MAINTAINER = 'Dyn'
API_BASE_URL = 'https://localhost:8080/'
########## End configuration block

require 'sinatra'

require 'ridley'
require 'time'
require 'zlib'
require 'archive/tar/minitar'

include Archive::Tar

def get_chef_client
  ridley = Ridley.new(
    server_url: CHEF_SERVER_URL,
    client_name: CHEF_CLIENT_NAME,
    client_key: CHEF_CLIENT_KEY,
    ssl: {
      verify: false
    }
  )
  ridley
end

def get_cookbook_list(_versions = 1)
  ridley = get_chef_client
  ridley.cookbook.all
end

def get_cookbook(cookbook, version, path)
  ridley = get_chef_client
  ridley.cookbook.download(cookbook, version, path)
end

get '/' do
  content_type :json
  response = {}
  response[:items] = []
  cookbook_list = get_cookbook_list
  response[:total] = cookbook_list.length
  cookbook_list.keys.each do |name|
    cookbook = {}
    cookbook['cookbook_name'] = name
    cookbook['cookbook_description'] = name
    cookbook['cookbook'] = File.join(API_BASE_URL, name)
    cookbook['cookbook_maintainer'] = COOKBOOK_MAINTAINER
    response[:items].push(cookbook)
  end
  response.to_json
end

get '/all' do
  content_type :json
  cookbook_list = get_cookbook_list
  cookbook_list.to_json
end

get '/:name' do
  content_type :json
  name = params[:name]
  my_cookbook = get_cookbook_list[name]
  response = {}
  response[:name] = name
  response[:category] = COOKBOOK_MAINTAINER
  response[:updated_at] = Time.now.iso8601
  response[:maintainer] = COOKBOOK_MAINTAINER
  response[:latest_version] = File.join(API_BASE_URL, name, 'versions', my_cookbook.first.gsub('.', '_'))
  response[:external_url] = nil
  response[:versions] = []
  my_cookbook.each do |version|
    response[:versions].push File.join(API_BASE_URL, name, 'versions', version.gsub('.', '_'))
  end
  response[:description] = name
  response[:average_rating] = nil
  response[:created_at] = Time.now.iso8601
  response.to_json
end

get '/:name/versions/:version' do
  content_type :json
  name = params[:name]
  version = params[:version].gsub('_', '.')

  unless File.exist?(File.join('cookbook-cache', "#{name}-#{version}.tgz"))
    Dir.mkdir(name)
    get_cookbook(name, version, name)
    tgz = Zlib::GzipWriter.new(File.open(File.join('cookbook-cache', "#{name}-#{version}.tgz"), 'wb'))
    Minitar.pack(name, tgz)
    FileUtils.rm_rf(name)
  end
  f = File.open(File.join('cookbook-cache', "#{name}-#{version}.tgz"), 'r')
  cookbook_size = f.size
  f.close

  response = {}
  response[:license] = 'Restricted'
  response[:updated_at] = Time.now.iso8601
  response[:tarball_file_size] = cookbook_size
  response[:version] = version
  response[:average_rating] = nil
  response[:cookbook] = File.join(API_BASE_URL, name)
  response[:created_at] = Time.now.iso8601
  response[:file] = File.join(API_BASE_URL, 'files', name, "#{version.gsub('.', '_')}.tgz")
  response.to_json
end

get '/files/:name/:version' do
  content_type 'application/x-gzip'
  version = params[:version].split('.')[0].gsub('_', '.')
  name = params[:name]

  unless File.exist?(File.join('cookbook-cache', "#{name}-#{version}.tgz"))
    Dir.mkdir(name)
    get_cookbook(name, version, name)
    tgz = Zlib::GzipWriter.new(File.open(File.join('cookbook-cache', "#{name}-#{version}.tgz"), 'wb'))
    Minitar.pack(name, tgz)
    FileUtils.rm_rf(name)
  end
  f = File.open(File.join('cookbook-cache', "#{name}-#{version}.tgz"), 'r')
  contents = f.read
  f.close
  return contents
end
