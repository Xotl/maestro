# (c) Copyright 2014 Hewlett-Packard Development Company, L.P.
# 
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
# 
#        http://www.apache.org/licenses/LICENSE-2.0
# 
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
node /^review.*/ inherits default {

  #
  # all nodes should meet these requirements.
  #
  include cdk_project::pip

  if !defined(Class['pip::python2']) {
    include pip::python2
  }

  # custom settings for local vagrant testing

  $override_vhost = true
  # this configuration should be different if we are registered with a dns
  # name.   For now we use ipv4, otherwise we would use fqdn

  # system config
  if str2bool($::vagrant_guest) == true {
    notice( 'Using vagrant configuration for local testing' )
    $def_container_heaplimit = '112m'
    $gerrit_vhost      = 'precise32'
    $gerrit_server     = $node_server
    $gerrit_server_url = "https://${gerrit_server}:8443/"
  } else {
    # large systems should be 8gb
    # TODO: we should have a class that defines systems
    $def_container_heaplimit = '900m'
    if $override_vhost {
      $gerrit_server     = $node_server
      $gerrit_vhost      = $gerrit_server
      $gerrit_server_url = "https://${gerrit_server}/"
    } else {
      $gerrit_server     = $fqdn
      $gerrit_vhost      = $gerrit_server
      $gerrit_server_url = "https://${gerrit_server}/"
    }
  }

  ::sysadmin_config::setup { 'setup gerrit ports':
      iptables_public_tcp_ports  => [80, 443, 8139, 8140, 29418, 8080],
      sysadmins                  => $sysadmins,
  } ->
  ::sysadmin_config::swap { '512':} ->

  notify{ "Openstack gerrit blueprint working for ${gerrit_server}": } ->

  class { 'cdk_project::gerrit':
    serveradmin                     => "webmaster@${::domain}",
    ssl_cert_file                   => "/etc/ssl/certs/${::fqdn}.pem",
    ssl_key_file                    => "/etc/ssl/private/${::fqdn}.key",
    ssl_chain_file                  => '/etc/ssl/certs/intermediate.pem',

    # these will be automatically created if we pass them in empty.
    ssl_cert_file_contents          => '',
    ssl_key_file_contents           => '',
    ssl_chain_file_contents         => '',

    # Working with a test server, generate some keys
    ssh_dsa_key_contents            => '',
    ssh_dsa_pubkey_contents         => '',
    ssh_rsa_key_contents            => '',
    ssh_rsa_pubkey_contents         => '',
    ssh_project_rsa_key_contents    => '',
    ssh_project_rsa_pubkey_contents => '',

    email                           => "review@${::domain}",
    # 1 + 100 + 9 + 2 + 2 + 25 = 139(rounded up)
    database_poollimit              => '150',
    container_heaplimit             => $def_container_heaplimit,
    core_packedgitopenfiles         => '4096',
    core_packedgitlimit             => '400m',
    core_packedgitwindowsize        => '16k',
    sshd_threads                    => '100',
    httpd_maxwait                   => '5000min',
    war                             => 'http://tarballs.openstack.org/ci/gerrit-2.4.4-14-gab7f4c1.war',
    contactstore                    => false,
    contactstore_appsec             => '',
    contactstore_pubkey             => '',
    contactstore_url                => 'http://www.openstack.org/verify/member/',
    script_user                     => 'gerrit2',
    script_key_file                 => '/home/gerrit2/.ssh/gerrit2',
    script_logging_conf             => '/home/gerrit2/.sync_logging.conf',
    projects_file                   => 'review.projects.yaml.erb',
    github_username                 => '',  # "${::domain}-gerrit",
    github_oauth_token              => '',
    github_project_username         => '',
    github_project_password         => '',
    mysql_password                  => hiera('mysql_password'),
    mysql_root_password             => hiera('mysql_root_password'),
    trivial_rebase_role_id          => "trivial-rebase@review.${::domain}",
    #TODO needs autogeneration at some point
    email_private_key               => 'FU7D198KY5xEx55/+YA1piHcfhwy/fo8sZk=',
    sysadmins                       => '',
    swift_username                  => '',
    swift_password                  => '',
    replication                     => [
      {
        name                 => 'local',
        url                  => 'file:///var/lib/git/',
        replicationDelay     => '0',
        threads              => '4',
        mirror               => true,
      }
    ],
    canonicalweburl                 => $gerrit_server_url,
    vhost_name                      => $gerrit_vhost,
    ip_vhost_name                   => $gerrit_server,
    runtime_module                  => 'runtime_project',
    override_vhost                  => $override_vhost,
    require                         => Class['cdk_project::pip'],
    demo_enabled                    => true,
    buglinks_enabled                => true,
  }
}

#
# we need a utilities server until we fix puppet master bug that prevents server restart, so we can consolidate
node /^util.*/ inherits default {

  $zuul_url = read_json('zuul','tool_url',$::json_config_location,false)
  if $zuul_url != '' and $zuul_url != '#'
  {
    $statsd_hosts = [$zuul_url]
    $rules = regsubst ($statsd_hosts, '^(.*)$', '-m udp -p udp -s \1 --dport 8125 -j ACCEPT')
  }
  else
  {
    $rules = ''
  }
  ::sysadmin_config::setup { 'setup util node ports':
    iptables_public_tcp_ports => [22, 80, 443, 8080, 8081, 8125, 2003, 8080],
    iptables_rules4           => $rules,
    sysadmins                 => $sysadmins,
  }
}

#
# this is the jenkins/zuul server
node /^ci.*/ inherits default {

  #$iptables_rules = regsubst ($gearman_workers, '^(.*)$', '-m state --state NEW -m tcp -p tcp --dport 4730 -s \1 -j ACCEPT')
  #$iptables_rule = regsubst ($zmq_event_receivers, '^(.*)$', '-m state --state NEW -m tcp -p tcp --dport 8888 -s \1 -j ACCEPT')
  ::sysadmin_config::setup { 'setup jenkins, zuul and gearman ports':
    iptables_public_tcp_ports   => [80, 443, 8080, 4730, 29418, 8139, 8140],
    # iptables_rules6           => $iptables_rules,
    # iptables_rules4           => $iptables_rules,
    sysadmins                   => $sysadmins,
  }
}

node /^wiki.*/ inherits default {

#
# all nodes should meet these requirements.
#
  class{'cdk_project::pip':} ->
  class { 'openstack_project::wiki':
    mysql_root_password     => hiera('wiki_db_password'),
    sysadmins               => hiera('sysadmins'),
    ssl_cert_file_contents  => hiera('wiki_ssl_cert_file_contents'),
    ssl_key_file_contents   => hiera('wiki_ssl_key_file_contents'),
    ssl_chain_file_contents => hiera('wiki_ssl_chain_file_contents'),
  }
}