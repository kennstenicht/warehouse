action :install do

  home_path = ::File.join node[:central][:apps], new_resource.name

  log %{Creating user for application <b>#{new_resource.name}</b>...}
  access_user new_resource.name do
    name new_resource.name
    group new_resource.name
    home home_path
  end

  envs_path = ::File.join node[:central][:envs], new_resource.name

  log %{Ensuring bash envs for #{new_resource.name}...}
  template envs_path do
    cookbook 'application'
    source   'envs.erb'
    owner    node[:whoami][:user]
    group    node[:whoami][:group]
    mode     '644'
    variables({
      envs: new_resource.environment_variables,
    })
    not_if { new_resource.environment_variables.empty? }
    notifies :restart, 'service[nginx]'
  end

  site_path = node[:passenger][:config_path].join(new_resource.name).to_s
  config_path = "#{site_path}.conf"
  public_path = ::File.join home_path, 'repository/public'
  log_path = ::File.join(node[:central][:log], new_resource.name)

  log %{Ensuring Nginx config paths for #{new_resource.name}...}

  paths = [site_path, ::File.join(site_path, 'before'), ::File.join(site_path, 'inside'), log_path]
  paths.each do |path|
    directory path do
      recursive true
      mode '0755'
      owner new_resource.name
      group new_resource.name
    end
  end

  log %{Configuring Nginx for #{new_resource.name}...}

  template config_path do
    cookbook 'application'
    source 'nginx/server.conf.erb'
    mode '0644'
    variables({
      name:        new_resource.name,
      site_path:   site_path,
      public_path: public_path,
      server_name: new_resource.domains,
      ssl:         new_resource.ssl,
      log_path:    log_path,
    })
    only_if { new_resource.passenger }
    notifies :restart, 'service[nginx]'
  end

  dirs = [new_resource.name, "#{new_resource.name}/before", "#{new_resource.name}/inside"]
  dirs.each do |dir_name|
    directory ::File.join(node[:passenger][:config_path], dir_name) do
      recursive true
      mode '0755'
      owner new_resource.name
      group new_resource.name
    end
  end

  if new_resource.asset_pipeline
    template "#{site_path}/inside/assets.conf" do
      cookbook 'application'
      source 'nginx/assets.conf.erb'
      variables( public_path: public_path )
      notifies :restart, 'service[nginx]'
    end
  end

end