BUILD_ROOT="/builds"
NAME="sas"
GIT_URL="git@github.com:foxsoft/sasweb.git"
GIT_BRANCH="master"
RECIPIENTS="omar@omarqureshi.net"

# Load RVM into a shell session *as a function*
if [[ -s "$HOME/.rvm/scripts/rvm" ]] ; then

  # First try to load from a user install
  source "$HOME/.rvm/scripts/rvm"

elif [[ -s "/usr/local/rvm/scripts/rvm" ]] ; then

  # Then try to load from a root install
  source "/usr/local/rvm/scripts/rvm"

else

  printf "ERROR: An RVM installation was not found.\n"

fi
# create database

cd $BUILD_ROOT
sqlite3 builds.db  "create table if not exists builds (id integer primary key,
                                                       name text,
                                                       commit_id text,
                                                       status text,
                                                       author text,
                                                       built_at datetime);"

sqlite3 builds.db "create unique index if not exists commit_id_idx on builds(commit_id)"

cleanup() {
  if [[ -n "$LOG" && -f "$LOG" ]]; then
      rm $LOG
  fi
}

while :
do
  LOG=`mktemp /tmp/build-$NAME.XXXXXX`
  trap cleanup EXIT
  
  cd $BUILD_ROOT
  if [ ! -e $NAME ]; then 
    mkdir $NAME
  fi
  
  cd $NAME
  if [ ! -e ".git" ]; then
    cd ..
    git clone $GIT_URL $NAME
    cd $NAME
  fi
  
  rvm rvmrc trust > /dev/null
  
  AUTHOR=`git show | head -2 | grep "Author" | awk 'BEGIN { FS = "[:<]" }; { print $2 }'`
  COMMIT=`git show | head -1 | awk '{print $2}'`
  STATUS="pass"
  
  OLD_TEST=`sqlite3 $BUILD_ROOT/builds.db "select * from builds where commit_id = '$COMMIT'"`
  
  if [[ -z $OLD_TEST ]]; then
    git pull > /dev/null

    if ! which bundle > /dev/null; then
      gem install bundler
    fi

    cp config/database.template.yml config/database.yml
    bundle > /dev/null
    rake db:drop:all > /dev/null
    rake db:create:all > /dev/null
    rake db:migrate RAILS_ENV=development > /dev/null
    
    
    if ! rake test > $LOG; then
      echo "\n" >> $LOG
      echo $AUTHOR >> $LOG
      echo $COMMIT >> $LOG
      mail -s "Tests broken by $AUTHOR at $COMMIT" $RECIPIENTS < $LOG
      STATUS="fail"
    fi

    cd $BUILD_ROOT
    sqlite3 builds.db "insert into builds(name, author, commit_id, status, built_at) values 
                                         (\"$NAME\", \"$AUTHOR\", \"$COMMIT\", \"$STATUS\", datetime('now'))"
  fi
  
  rm $LOG

  sleep 20
done
