#!/bin/bash
DB_PASS=${DB_PASS:-1q2w3e4r5t}
DB_HOST_VOLUME=${DB_HOST_VOLUME:-}
ADMIN_PASS=${ADMIN_PASS:-shipyard}
TAG=${TAG:-latest}
DEBUG=${DEBUG:-False}
ACTION=${1:-}
if [ ! -e "/docker.sock" ] ; then
    echo "You must map your Docker socket to /docker.sock (i.e. -v /var/run/docker.sock:/docker.sock)"
    exit 2
fi

if [ -z "$ACTION" ] ; then
    echo "Usage: "
    echo "  shipyard/deploy <action>"
    echo ""
    echo "Examples: "
    echo "  docker run shipyard/deploy setup"
    echo "     Deploys Shipyard stack"
    echo "  docker run shipyard/deploy cleanup"
    echo "     Removes Shipyard stack"
    exit 1
fi

function cleanup {
    for CNT in shipyard shipyard_redis shipyard_router shipyard_db shipyard_lb
    do
        docker -H unix://docker.sock kill $CNT > /dev/null 2>&1
        docker -H unix://docker.sock rm $CNT > /dev/null 2>&1
    done
}

function purge {
    cleanup
    for IMG in shipyard redis router db lb
    do
        docker -H unix://docker.sock rmi shipyard/$IMG > /dev/null 2>&1
    done
}

if [ "$ACTION" = "setup" ] ; then

    cat /archives/ubuntu.tar | docker -H unix://docker.sock import - ubuntu
    cat /archives/shipyard_db.tar | docker -H unix://docker.sock import - shipyard/db
    cat /archives/shipyard_latest.tar | docker -H unix://docker.sock import - shipyard/shipyard:latest
    cat /archives/shipyard_lb.tar | docker -H unix://docker.sock import - shipyard/lb
    cat /archives/shipyard_redis.tar | docker -H unix://docker.sock import - shipyard/redis
    cat /archives/shipyard_router.tar | docker -H unix://docker.sock import - shipyard/router

    echo "
Using $TAG tag for Shipyard
This may take a moment while the Shipyard images are pulled..."
    echo "Starting Redis..."
    redis=$(docker -H unix://docker.sock run -i -t -d -p 6379:6379 --name shipyard_redis shipyard/redis /usr/local/bin/redis-server /etc/redis.conf)
    sleep 5
    echo "Starting App Router..."
    router=$(docker -H unix://docker.sock run -i -t -d -p 80 --link shipyard_redis:redis --name shipyard_router shipyard/router /bin/sh -e /usr/local/bin/run)
    sleep 5
    echo "Starting Load Balancer..."
    lb=$(docker -H unix://docker.sock run -i -t -d -p 80:80 --link shipyard_redis:redis --link shipyard_router:app_router --name shipyard_lb shipyard/lb /bin/sh -e /usr/local/bin/run)
    sleep 5
    echo "Starting DB..."
    EXTRA_DB_ARGS=""
    if [ ! -z "$DB_HOST_VOLUME" ] ; then
        EXTRA_DB_ARGS="-v $DB_HOST_VOLUME:/var/lib/postgresql"
    fi
    db=$(docker -H unix://docker.sock run -i -t -d -p 5432 -e DB_NAME=shipyard -e DB_USER=shipyard -e DB_PASS=$DB_PASS $EXTRA_DB_ARGS --name shipyard_db shipyard/db /bin/bash -e /usr/local/bin/run)
    sleep 5
    echo "Starting Shipyard"
    shipyard=$(docker -H unix://docker.sock run -i -t -d -p 8000:8000 --link shipyard_db:db --link shipyard_redis:redis --name shipyard -e ADMIN_PASS=$ADMIN_PASS -e DEBUG=$DEBUG shipyard/shipyard:$TAG /app/.docker/run.sh app master-worker)
    echo "
Shipyard Stack Deployed

You should be able to login with admin:$ADMIN_PASS at http://<docker-host-ip>:8000
You will also need to setup and register the Shipyard Agent.  See http://github.com/shipyard/shipyard-agent for details.
"
elif [ "$ACTION" = "cleanup" ] ; then
    cleanup
    echo "Shipyard Stack Removed"
elif [ "$ACTION" = "purge" ] ; then
    echo "Removing Shipyard images.  This could take a moment..."
    purge
fi


