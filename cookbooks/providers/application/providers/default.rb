action :install do

  if new_resource.letsencrypt

    log %{Install certbot-auto...}

    # This causes a `EOFError: end of file reached` for some weird reason.
    # remote_file '/usr/local/bin/certbot-auto' do
    #   source 'https://dl.eff.org/certbot-auto'
    #   owner 'root'
    #   group 'root'
    #   mode '0755'
    # end

    # Use this instead for now:
    execute 'download certbot-auto' do
      user 'root'
      command 'wget https://dl.eff.org/certbot-auto -O /usr/local/bin/certbot-auto'
    end

    # In combination with this:
    file '/usr/local/bin/certbot-auto' do
      action :touch
      owner 'root'
      group 'root'
      mode '0755'
    end

    log %{Update certbot-auto...}
    execute 'update certbot-auto' do
      user 'root'
      command 'certbot-auto --non-interactive config_changes'
    end

    log %{Install certbot-auto cron...}
    cron 'certbot-auto renew' do
      minute  0
      hour    5
      command '/usr/local/bin/certbot-auto renew --quiet --non-interactive --no-self-upgrade --deploy-hook "/usr/sbin/service nginx restart"'
    end
  end

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
    notifies :stop, 'service[nginx]'
    notifies :start, 'service[nginx]'
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

  log %{Enable logrotation...}
  template "/etc/logrotate.d/nginx-#{new_resource.name}" do
    cookbook 'passenger'
    owner "root"
    group "root"
    source "logrotate.erb"
    variables({
      log_path: "#{log_path}/*.log"
    })
    mode "644"
  end

  if new_resource.letsencrypt && Pathname.new(public_path).exist?
    log %{Obtain let's encrypt certificate...}

    # We optain a certificate for every domain and use www and non www
    domains = new_resource.domains.split(' ')
    domains.each do |domain|
      letsencrypt_domains = "#{domain} -d #{domain.gsub('www.', '')}"

      execute "obtain cert for #{domain}" do
        user 'root'
        command "certbot-auto certonly --non-interactive --webroot -w #{public_path} -d #{letsencrypt_domains} --email #{new_resource.letsencrypt_email} --agree-tos"
      end
    end
  end

  log %{Configuring Nginx for #{new_resource.name}...}

  template config_path do
    cookbook 'application'
    source 'nginx/server.conf.erb'
    mode '0644'
    variables({
      name:             new_resource.name,
      site_path:        site_path,
      public_path:      public_path,
      server_name:      new_resource.domains,
      ssl:              new_resource.ssl,
      letsencrypt:      new_resource.letsencrypt,
      log_path:         log_path,
    })
    only_if { new_resource.passenger }
    notifies :stop, 'service[nginx]'
    notifies :start, 'service[nginx]'
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
      notifies :stop, 'service[nginx]'
      notifies :start, 'service[nginx]'
    end
  end

end
