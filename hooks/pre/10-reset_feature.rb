# See bottom of the script for the command that kicks off the script

def reset
  if foreman_installed?

    stop_services
    reset_database
    reset_candlepin
    reset_pulp

  else
    Kafo::KafoConfigure.logger.warn 'Katello not installed yet, can not drop database!'
  end
end

def foreman_installed?
  `which foreman-rake > /dev/null 2>&1`
  $?.success?
end

def stop_services
  Kafo::KafoConfigure.logger.info 'Stopping services'
  Kafo::Helpers.execute('katello-service stop --exclude postgresql')
end

def reset_database
  Kafo::KafoConfigure.logger.info 'Dropping database!'
  Kafo::Helpers.execute('foreman-rake db:drop 2>&1')
end

def reset_candlepin
  Kafo::KafoConfigure.logger.info 'Dropping Candlepin database!'

  tomcat = File.exists?('/var/lib/tomcat') ? 'tomcat' : 'tomcat6'
  commands = [
    'rm -f /var/lib/candlepin/cpdb_done',
    'rm -f /var/lib/candlepin/cpinit_done',
    "service #{tomcat} stop",
    'sudo su postgres -c "dropdb candlepin"'
  ]

  Kafo::Helpers.execute(commands)
end

def empty_mongo
  mongo_config = load_mongo_config
  if remote_host?(mongo_config[:host])
    empty_remote_mongo(mongo_config)
  else
    Kafo::Helpers.execute(
      [
        'service-wait mongod stop',
        'rm -f /var/lib/mongodb/pulp_database*',
        'service-wait mongod start'
      ]
    )
  end
end

def load_mongo_config
  config = {}
  seeds = param('katello', 'pulp_db_seeds').value
  host, port = seeds.split(':') if seeds
  config[:host] = host || 'localhost'
  config[:port] = port || '27017'
  config[:database] = param('katello', 'pulp_db_name').value || 'pulp_database'
  config[:username] = param('katello', 'pulp_db_username').value
  config[:password] = param('katello', 'pulp_db_password').value
  config[:ssl] = param('katello', 'pulp_db_ssl').value || false
  config[:ca_path] = param('katello', 'pulp_db_ca_path').value
  config
end

def empty_remote_mongo(config)
  ssl = "--ssl" if config[:ssl]
  ca_cert = "--sslCAFile #{config[:ca_path]}" if config[:ca_path]
  credentials = "-u #{config[:username]} -p #{config[:password]}"
  host = "--host #{config[:host]} --port #{config[:port]}"
  cmd = "mongo #{credentials} #{host} #{ssl} #{ca_cert} --eval \"db.dropDatabase();\" #{config[:database]}"
  Kafo::Helpers.execute(cmd)
end

def reset_pulp
  Kafo::KafoConfigure.logger.info 'Dropping Pulp database!'

  Kafo::Helpers.execute(
    [
      'rm -f /var/lib/pulp/init.flag',
      'service-wait httpd stop'
    ]
  )
  empty_mongo
  Kafo::Helpers.execute(
    'rm -rf /var/lib/pulp/{distributions,published,repos}/*'
  )
end

def remote_host?(hostname)
  !['localhost', '127.0.0.1', `hostname`.strip].include?(hostname)
end

if app_value(:reset) && !app_value(:noop)
  response = ask('Are you sure you want to continue? This will drop the databases, reset all configurations that you have made and bring the server back to a fresh install. [y/n]')
  if response.downcase != 'y'
    $stderr.puts '** cancelled **'
    kafo.class.exit(1)
  else
    reset
  end
end
