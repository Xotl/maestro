# == Class: ::puppet::autosign
#
# (c) Copyright 2014 Hewlett-Packard Development Company, L.P.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# setup an autosign.conf based on hosts list
class puppet::autosign (
  $nodes       = [$::fqdn],
  $extra_nodes = hiera_array('puppet::autosign::nodes', [])
  ) {
  file { '/etc/puppet/autosign.conf':
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('puppet/autosign.conf.erb'),
  }
}
