#!/bin/bash
# Tru-Strap: prepare an instance for a Puppet run

main() {
    parse_args "$@"
    install_yum_deps
    install_ruby
    install_gem_deps
    symlink_puppet_dir
    fetch_puppet_modules
    run_puppet
}

usagemessage="Error, USAGE: $(basename "${0}") \n \
  --role|-r \n \
  --environment|-e \n \
  --repouser|-u \n \
  --reponame|-n \n \
  --repoprivkeyfile|-k \n \
  [--repotoken|-t] \n \
  [--repobranch|-b] \n \
  [--repodir|-d] \n \
  [--eyamlpubkeyfile|-j] \n \
  [--eyamlprivkeyfile|-m] \n \
  [--gemsources|-s] \n \
  [--help|-h] \n \
  [--version|-v]"

function log_error() {
    echo "###############------Fatal error!------###############"
    caller
    printf "%s\n" "${1}"
    exit 1
}

# Parse the commmand line arguments
parse_args() {
  while [[ -n "${1}" ]] ; do
    case "${1}" in
      --help|-h)
        echo -e ${usagemessage}
        exit
        ;;
      --version|-v)
        print_version "${PROGNAME}" "${VERSION}"
        exit
        ;;
      --role|-r)
        set_facter init_role "${2}"
        shift
        ;;
      --environment|-e)
        set_facter init_env "${2}"
        shift
        ;;
      --debug)
        shift
        ;;
      *)
        echo "Unknown argument: ${1}"
        echo -e "${usagemessage}"
        exit 1
        ;;
    esac
    shift
  done

  # Define required parameters.
  if [[ -z "${FACTER_init_role}" || \
        -z "${FACTER_init_env}"  ]]; then
    echo -e "${usagemessage}"
    exit 1
  fi
}

# Install yum packages if they're not already installed
yum_install() {
  for i in "$@"
  do
    if ! rpm -q ${i} > /dev/null 2>&1; then
      local RESULT=''
      RESULT=$(yum install -y ${i} 2>&1)
      if [[ $? != 0 ]]; then
        log_error "Failed to install yum package: ${i}\nyum returned:\n${RESULT}"
      else
        echo "Installed yum package: ${i}"
      fi
    fi
  done
}

# Install Ruby gems if they're not already installed
gem_install() {
  local RESULT=''
  for i in "$@"
  do
    if [[ ${i} =~ ^.*:.*$ ]];then
      MODULE=$(echo ${i} | cut -d ':' -f 1)
      VERSION=$(echo ${i} | cut -d ':' -f 2)
      if ! gem list -i --local ${MODULE} --version ${VERSION} > /dev/null 2>&1; then
        echo "Installing ${i}"
        RESULT=$(gem install ${i} --no-ri --no-rdoc)
        if [[ $? != 0 ]]; then
          log_error "Failed to install gem: ${i}\ngem returned:\n${RESULT}"
        fi
      fi
    else
      if ! gem list -i --local ${i} > /dev/null 2>&1; then
        echo "Installing ${i}"
        RESULT=$(gem install ${i} --no-ri --no-rdoc)
        if [[ $? != 0 ]]; then
          log_error "Failed to install gem: ${i}\ngem returned:\n${RESULT}"
        fi
      fi
    fi
  done
}

print_version() {
  echo "${1}" "${2}"
}

# Set custom facter facts
set_facter() {
  local key=${1}
  #Note: The name of the evironment variable is not the same as the facter fact.
  local export_key=FACTER_${key}
  local value=${2}
  export ${export_key}="${value}"
  if [[ ! -d /etc/facter ]]; then
    mkdir -p /etc/facter/facts.d || log_error "Failed to create /etc/facter/facts.d"
  fi
  if ! echo "${key}=${value}" > /etc/facter/facts.d/"${key}".txt; then
    log_error "Failed to create /etc/facter/facts.d/${key}.txt"
  fi
  chmod -R 600 /etc/facter || log_error "Failed to set permissions on /etc/facter"
  cat /etc/facter/facts.d/"${key}".txt || log_error "Failed to create ${key}.txt"
}

install_ruby() {
  majorversion=$(lsb_release -rs | cut -f1 -d.)
  ruby_v="2.1.5"
  ruby -v  > /dev/null 2>&1
  if [[ $? -ne 0 ]] || [[ $(ruby -v | awk '{print $2}' | cut -d 'p' -f 1) != $ruby_v ]]; then
    yum remove -y ruby-* || log_error "Failed to remove old ruby"
    yum_install https://s3-eu-west-1.amazonaws.com/msm-public-repo/ruby/ruby-2.1.5-2.el${majorversion}.x86_64.rpm
  fi
}



# Install the yum dependencies
install_yum_deps() {
  echo "Installing required yum packages"
  yum_install augeas-devel ncurses-devel gcc gcc-c++ curl git redhat-lsb-core
}

# Install the gem dependencies
install_gem_deps() {
  echo "Installing puppet and related gems"
  gem_install puppet:3.7.4 hiera facter ruby-augeas hiera-eyaml ruby-shadow
}


# Symlink the cloned git repo to the usual location for Puppet to run
symlink_puppet_dir() {
  local RESULT=''
  # Link /etc/puppet to our private repo.
  PUPPET_DIR="/vagrant/puppet"
  if [ -e /etc/puppet ]; then
    RESULT=$(rm -rf /etc/puppet);
    if [[ $? != 0 ]]; then
      log_error "Failed to remove /etc/puppet\nrm returned:\n${RESULT}"
    fi
  fi

  RESULT=$(ln -s "${PUPPET_DIR}" /etc/puppet)
  if [[ $? != 0 ]]; then
    log_error "Failed to create symlink from ${PUPPET_DIR}\nln returned:\n${RESULT}"
  fi

  if [ -e /etc/hiera.yaml ]; then
    RESULT=$(rm -f /etc/hiera.yaml)
    if [[ $? != 0 ]]; then
      log_error "Failed to remove /etc/hiera.yaml\nrm returned:\n${RESULT}"
    fi
  fi

  RESULT=$(ln -s /etc/puppet/hiera.yaml /etc/hiera.yaml)
  if [[ $? != 0 ]]; then
    log_error "Failed to create symlink from /etc/hiera.yaml\nln returned:\n${RESULT}"
  fi
}


run_librarian() {
  gem_install activesupport:4.2.6 librarian-puppet
  echo -n "Running librarian-puppet"
  local RESULT=''
  RESULT=$(librarian-puppet install --verbose)
  if [[ $? != 0 ]]; then
    log_error "librarian-puppet failed.\nThe full output was:\n${RESULT}"
  fi
  librarian-puppet show
}

# Fetch the Puppet modules via the moduleshttpcache or librarian-puppet
fetch_puppet_modules() {
  ENV_BASE_PUPPETFILE="${FACTER_init_env}/Puppetfile.base"
  ENV_ROLE_PUPPETFILE="${FACTER_init_env}/Puppetfile.${FACTER_init_role}"
  BASE_PUPPETFILE=Puppetfile.base
  ROLE_PUPPETFILE=Puppetfile."${FACTER_init_role}"
  if [[ -f "/etc/puppet/Puppetfiles/${ENV_BASE_PUPPETFILE}" ]]; then
    BASE_PUPPETFILE="${ENV_BASE_PUPPETFILE}"
  fi
  if [[ -f "/etc/puppet/Puppetfiles/${ENV_ROLE_PUPPETFILE}" ]]; then
    ROLE_PUPPETFILE="${ENV_ROLE_PUPPETFILE}"
  fi
  PUPPETFILE=/etc/puppet/Puppetfile
  rm -f "${PUPPETFILE}" ; cat /etc/puppet/Puppetfiles/"${BASE_PUPPETFILE}" > "${PUPPETFILE}"
  echo "" >> "${PUPPETFILE}"
  cat /etc/puppet/Puppetfiles/"${ROLE_PUPPETFILE}" >> "${PUPPETFILE}"

  cd "${PUPPET_DIR}" || log_error "Failed to cd to ${PUPPET_DIR}"

  run_librarian
}

# Execute the Puppet run
run_puppet() {
  export LC_ALL=en_GB.utf8
  echo ""
  echo "Running puppet apply"
  puppet apply /etc/puppet/manifests/site.pp --detailed-exitcodes

  PUPPET_EXIT=$?

  case $PUPPET_EXIT in
    0 )
      echo "Puppet run succeeded with no failures."
      ;;
    1 )
      log_error "Puppet run failed."
      ;;
    2 )
      echo "Puppet run succeeded, and some resources were changed."
      ;;
    4 )
      log_error "Puppet run succeeded, but some resources failed."
      ;;
    6 )
      log_error "Puppet run succeeded, and included both changes and failures."
      ;;
    * )
      log_error "Puppet run returned unexpected exit code."
      ;;
  esac
}

main "$@"
