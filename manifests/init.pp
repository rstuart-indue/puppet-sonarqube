# Copyright 2011 MaestroDev
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
class sonarqube (
  $version          = '6.7.5',
  $package_name     = 'sonarqube',
  $testing          = false,
  $user             = 'sonar',
  $group            = 'sonar',
  $user_system      = true,
  $service          = 'sonar',
  $installroot      = '/opt',
  $home             = undef,
  $host             = undef,
  $port             = 9000,
  $port_ajp          = -1,
  $download_url     = 'https://binaries.sonarsource.com/Distribution/sonarqube',
  $download_dir     = '/tmp',
  $context_path     = '/',
  $arch             = $sonarqube::params::arch,
  $https            = {},
  $ldap             = {},
  # ldap and pam are mutually exclusive. Setting $ldap will annihilate the setting of $pam
  $pam              = {},
  $crowd            = {},
  $jdbc             = {
    url                               => 'jdbc:h2:tcp://localhost:9092/sonar',
    username                          => 'sonar',
    password                          => 'sonar',
    max_active                        => '50',
    max_idle                          => '5',
    min_idle                          => '2',
    max_wait                          => '5000',
    min_evictable_idle_time_millis    => '600000',
    time_between_eviction_runs_millis => '30000',
  },
  $log_folder       = '/var/log/sonar',
  $updatecenter     = true,
  $http_proxy       = {},
  $no_proxy_hosts    = undef,
  $profile          = false,
  $web_java_opts    = undef,
  $search_java_opts = undef,
  $search_host      = '127.0.0.1',
  $search_port      = '9001',
  $config           = undef,
) inherits sonarqube::params {
  validate_absolute_path($download_dir)
  Exec {
    path => '/sbin:/usr/sbin:/usr/bin:/bin',
  }
  File {
    owner => $user,
    group => $group,
  }

  # wget from https://github.com/maestrodev/puppet-wget
  #include wget

  if $home != undef {
    $real_home = $home
  } else {
    $real_home = '/opt/sonar'
  }
  Sonarqube::Move_to_home {
    home => $real_home,
  }

  $extensions_dir = "${real_home}/extensions"
  $plugin_dir = "${extensions_dir}/plugins"

  $installdir = "${installroot}/${service}"
  $tmpzip = "${download_dir}/${package_name}-${version}.zip"
  $script = "${installdir}/bin/${arch}/sonar.sh"

  if ! defined(Package[unzip]) {
    package { 'unzip':
      ensure => present,
      before => Archive[$tmpzip],
    }
  }

  user { $user:
    ensure     => present,
    home       => $real_home,
    managehome => false,
    system     => $user_system,
  }

  -> group { $group:
    ensure => present,
    system => $user_system,
  }

#  -> wget::fetch { 'download-sonar':
#    source      => "${download_url}/${package_name}-${version}.zip",
#    destination => $tmpzip,
#  }

  # ===== Create folder structure =====
  # so uncompressing new sonar versions at update time use the previous sonar home,
  # installing new extensions and plugins over the old ones, reusing the db,...

  # Sonar home
  -> file { $real_home:
    ensure => directory,
    mode   => '0700',
  }

  -> file { "${installroot}/sonarqube-${version}":
    ensure => directory,
  }

  -> file { $installdir:
    ensure => link,
    target => "${installroot}/sonarqube-${version}",
    notify => Service['sonarqube.service'],
  }

  -> sonarqube::move_to_home {
    'data':
  }

  -> sonarqube::move_to_home {
    'extras':
  }

  -> sonarqube::move_to_home {
    'extensions':
  }

  -> sonarqube::move_to_home {
    'logs':
  }

  # ===== Install SonarQube =====
  -> archive { $tmpzip:
    source       => "${download_url}/${package_name}-${version}.zip",
    extract_path => $installroot,
    creates      => "${installroot}/sonarqube-${version}/bin",
    extract      => true,
    cleanup      => true,
    user         => $user,
    group        => $group,
  }

#  exec { 'untar':
#    command => "unzip -o ${tmpzip} -d ${installroot} && chown -R \
#      ${user}:${group} ${installroot}/sonarqube-${version} \
#      && chown -R ${user}:${group} ${real_home}",
#    creates => "${installroot}/sonarqube-${version}/bin",
#  }

  -> file { $script:
    mode    => '0755',
    content => template('sonarqube/sonar.sh.erb'),
  }

  systemd::unit_file { 'sonarqube.service':
    enable  => true,
    active  => true,
    content => template("${module_name}/sonar.service.erb"),
    require => File[$script],
  }
  systemd::service_limits { 'sonarqube.service':
    limits => {
      'LimitNOFILE' => '131072',
    },
  }

  # Sonar configuration files
  if $config != undef {
    file { "${installdir}/conf/sonar.properties":
      source  => $config,
      require => Archive[$tmpzip],
      notify  => Service['sonarqube.service'],
      mode    => '0600',
    }
  } else {
    file { "${installdir}/conf/sonar.properties":
      content => template('sonarqube/sonar.properties.erb'),
      notify  => Service['sonarqube.service'],
      mode    => '0600',
      require => Archive[$tmpzip],
    }
  }

  file { '/tmp/cleanup-old-plugin-versions.sh':
    content => template("${module_name}/cleanup-old-plugin-versions.sh.erb"),
    mode    => '0755',
  }

  -> file { '/tmp/cleanup-old-sonarqube-versions.sh':
    content => template("${module_name}/cleanup-old-sonarqube-versions.sh.erb"),
    mode    => '0755',
  }

  -> exec { 'remove-old-versions-of-sonarqube':
    command     => "/tmp/cleanup-old-sonarqube-versions.sh ${installroot} ${version}",
    refreshonly => true,
    subscribe   => File["${installroot}/sonarqube-${version}"],
  }

  # The plugins directory. Useful to later reference it from the plugin definition
  file { $plugin_dir:
    ensure => directory,
  }

}
