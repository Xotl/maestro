# Class: maestro::app::setup
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
# This module installs forj.config project
#
# Parameters:
# $user:: An String, example puppet
# $dir:: An String specifying path to extract forj.config
#
# Actions:
# (1) Installs nodejs
# (2) setup forj.config database
# (3) uses npm to install required nodejs packages
# (4) starts the rest api service

# Sample Usage:
# puppet apply -e "class { 'maestro::app::setup': }" --modulepath=/opt/config/production/git/maestro/puppet/modules:/etc/puppet/modules; --verbose


class maestro::app::setup(
  $user     = hiera('maestro::app::user','puppet'),
  $app_dir  = hiera('maestro::app::app_dir',"/opt/config/${::environment}/app"),
  $revision = hiera('maestro::app::setup::revision','master'),
){
  require maestro::app::kits_db
  require maestro::requirements

  validate_string($user)
  validate_string($app_dir)
  validate_string($revision)

  vcsrepo {"${app_dir}/forj.config":
    ensure   => latest,
    provider => 'git',
    revision => $revision,
    source   => 'https://review.forj.io/p/forj-ui/forj.config',
    require  => [ Package['optimist'],
                  Package['restify'],
                  Package['path'],
                  Package['mysql'],
                  Package['js-yaml'],
                  Package['pm2'],
                ]
  } ->
  nodejs_wrap::pm2instance{'kitops.js':
    script_dir => "${app_dir}/forj.config",
    user       => $user,
    require    => [   Nodejs_wrap::Pm2instance['maestro-app.js'],
                      Nodejs_wrap::Pm2instance['bp-app.js']
                    ],
  }
}
