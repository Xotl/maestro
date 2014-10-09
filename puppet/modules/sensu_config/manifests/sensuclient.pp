# == Class: sensu_config::sensuclient
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
# Installs SensuClient
#

class sensu_config::sensuclient (
  $sensu_vhost    = hiera('sensu_config::sensuclient::sensu_vhost','/sensu'),
  $password       = hiera('rabbit::password'),
  $rabbitmq_host  = hiera('rabbit::host',$::eroip),
  $subscriptions  = hiera('rabbit::subscriptions','sensu-test'),
  $redis_host     = hiera('redis::params::host',$::eroip),
  $redis_port     = hiera('redis::params::port','6379'),
)
{
  validate_string($password)
  validate_string($rabbitmq_host)
  validate_string($subscriptions)
  validate_string($redis_host)

  if !is_integer($redis_port) { fail('sensu_config::sensuclient::redis_port must be an integer') }

  if $password == '' {
    fail('ERROR! rabbit::sensuclient::password is required.')
  }

  class { 'sensu':
    rabbitmq_password  => $password,
    rabbitmq_host      => $rabbitmq_host,
    redis_host         => $redis_host,
    redis_port         => $redis_port,
    subscriptions      => $subscriptions,
    rabbitmq_vhost     => $sensu_vhost,
  }

  file { '/etc/sensu/plugins/check-disk.rb':
    ensure  => present,
    mode    => '0555',
    owner   => 'sensu',
    group   => 'sensu',
    source  => 'puppet:///modules/sensu_config/check-disk.rb',
    require => File['/etc/sensu/plugins'],
  }

  file { '/etc/sensu/plugins/check-cpu.rb':
    ensure  => present,
    mode    => '0555',
    owner   => 'sensu',
    group   => 'sensu',
    source  => 'puppet:///modules/sensu_config/check-cpu.rb',
    require => File['/etc/sensu/plugins'],
  }

  file { '/etc/sensu/plugins/check-mem.sh':
    ensure  => present,
    mode    => '0555',
    owner   => 'sensu',
    group   => 'sensu',
    source  => 'puppet:///modules/sensu_config/check-mem.sh',
    require => File['/etc/sensu/plugins'],
  }

  sensu::check{ 'check_disk':
    command      => '/opt/sensu/embedded/bin/ruby /etc/sensu/plugins/check-disk.rb -w 75 -c 85',
    subscribers  => $subscriptions,
    interval     => '1',
    require      => File['/etc/sensu/plugins/check-disk.rb'],
  }

  sensu::check{ 'check_cpu':
    command      => '/opt/sensu/embedded/bin/ruby /etc/sensu/plugins/check-cpu.rb',
    subscribers  => $subscriptions,
    interval     => '1',
    require      => File['/etc/sensu/plugins/check-cpu.rb'],
  }

  sensu::check{ 'check_mem':
    command      => '/etc/sensu/plugins/check-mem.sh',
    subscribers  => $subscriptions,
    interval     => '1',
    require      => File['/etc/sensu/plugins/check-mem.sh'],
  }
}