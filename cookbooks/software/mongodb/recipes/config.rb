username    = 'mongodb'
config_path = Pathname.new '/etc'
data_path   = Pathname.new node[:central][:data] + '/mongodb'
log_path    = Pathname.new node[:central][:log] + '/mongodb'

log 'Ensuring MongoDB database directory...'
directory data_path.to_s do
  owner username
  group username
  mode '0755'
end

log 'Ensuring persmissions for the MongoDB log file...'
file log_path.join('upstart.log').to_s do
  owner username
  group username
  mode '0644'
  action :touch
end


log 'Configuring MongoDB...'
template config_path.join('mongodb.conf').to_s do
  source "mongodb.conf.erb"
  owner username
  group username
  mode '0644'
  variables({
    data_path: data_path,
  })
  notifies :restart, 'service[mongodb]'
end