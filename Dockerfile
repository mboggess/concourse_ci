FROM openshift/origin-base

ENV LANG="en_US.UTF-8" LANGUAGE="en_US:en" LC_ALL="en_US.UTF-8"

LABEL io.k8s.display-name="OpenShift Custom Builder" \
      io.k8s.description="Docker Elsevier Builder"

COPY repos/ /etc/yum.repos.d/

RUN yum clean all && yum makecache fast && yum update -y && \
    yum groupinstall -y 'development tools'

RUN yum -y install epel-release && \
    yum clean all && yum makecache fast && yum update -y

RUN INSTALL_PKGS="sudo docker-engine gettext git curl unzip rsync tree which libpng-devel vim-enhanced moreutils" && \
    yum install -y $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    yum clean all

ARG JAVA_VERSION=1.8.0

RUN JAVA_PKGS="java-$JAVA_VERSION-openjdk java-$JAVA_VERSION-openjdk-devel" && \
  yum clean all && yum install -y $JAVA_PKGS && rpm -V $JAVA_PKGS

ENV JAVA_HOME /usr/lib/jvm/java

ARG MAVEN_VERSION=3.3.9
RUN curl -fsSL https://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz | tar xzf - -C /usr/share \
  && mv /usr/share/apache-maven-$MAVEN_VERSION /usr/share/maven \
  && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

ENV MAVEN_HOME /usr/share/maven

ARG GRADLE_VERSION=2.14
RUN curl -sL -0 https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip \
    -o /tmp/gradle-${GRADLE_VERSION}-bin.zip && \
    unzip /tmp/gradle-${GRADLE_VERSION}-bin.zip -d /usr/local/ && \
    rm /tmp/gradle-${GRADLE_VERSION}-bin.zip && \
    mv /usr/local/gradle-${GRADLE_VERSION} /usr/local/gradle && \
    ln -sf /usr/local/gradle/bin/gradle /usr/local/bin/gradle

RUN INSTALL_PKGS="ruby ruby-devel" && \
    yum install -y $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    gem install sass compass bundler && \
    yum clean all

ARG GOSU_VERSION=1.10
RUN set -x \
    && yum -y install wget dpkg \
    && dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" \
    && wget -O /usr/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch" \
    && wget -O /tmp/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && gpg --batch --verify /tmp/gosu.asc /usr/bin/gosu \
    && rm -r "$GNUPGHOME" /tmp/gosu.asc \
    && chmod +x /usr/bin/gosu \
    && gosu nobody true \
    && yum -y remove wget dpkg \
    && yum clean all

ARG SONAR_VERSION=2.8
RUN curl -sL -0 https://sonarsource.bintray.com/Distribution/sonar-scanner-cli/sonar-scanner-${SONAR_VERSION}.zip \
  -o /tmp/sonar-scanner-${SONAR_VERSION}.zip && \
  unzip /tmp/sonar-scanner-${SONAR_VERSION}.zip -d /usr/local/ && \
  rm /tmp/sonar-scanner-${SONAR_VERSION}.zip && \
  mv /usr/local/sonar-scanner-${SONAR_VERSION} /usr/local/sonar-scanner && \
  ln -sf /usr/local/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner

RUN yum makecache fast && yum install -y python python-pip jq && yum clean all && \
  pip install --upgrade pip setuptools requests

ARG OC_VERSION="3.6.1"
ARG OC_VERSION_HASH="008f2d5"
RUN curl -sL -0 https://github.com/openshift/origin/releases/download/v${OC_VERSION}/openshift-origin-client-tools-v${OC_VERSION}-${OC_VERSION_HASH}-linux-64bit.tar.gz | tar xzv && \
  mv openshift-origin-*/* /usr/bin/

RUN yum makecache fast && yum install -y google-chrome-stable && yum clean all && \
  yum remove google-chrome-stable -y

RUN useradd -ms /bin/bash builder && usermod -aG wheel builder && \
    echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/builder && \
    chown -R builder:builder /usr/local/sonar-scanner/conf/

ENV HOME=/home/builder
ENV GRADLE_USER_HOME=$HOME
WORKDIR /home/builder

RUN mkdir -p $HOME/.ssh && touch $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa
RUN echo -e "Host github.com\n\tStrictHostKeyChecking no\nHost gitlab.et-scm.com\n\tStrictHostKeyChecking no\n" \
 >> $HOME/.ssh/config

ENV NVM_DIR="$HOME/.nvm"
RUN git clone https://github.com/creationix/nvm.git "$NVM_DIR" && \
  pushd "$NVM_DIR" && \
  NVM_RELEASE=$(git describe --abbrev=0 --tags --match "v[0-9]*" origin) && \
  git checkout $NVM_RELEASE && . "$NVM_DIR/nvm.sh"
RUN echo $'export NVM_DIR="$HOME/.nvm"\n\
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'\
>> ~/.bashrc

ENV SCRIPT_DIR=/scripts
RUN mkdir -p $SCRIPT_DIR && echo "source ${SCRIPT_DIR}/init.sh" >> ~/.bashrc

RUN source $NVM_DIR/nvm.sh && nvm install node && \
  nvm use node && npm install -g semver grunt-cli grunt bower

RUN chown -R builder /home/builder

ENV SECRETS_DIR=/etc/secrets
VOLUME $SECRETS_DIR

#######################################

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

#######################################

COPY buildfiles/ /var/run/build/

COPY scripts $SCRIPT_DIR/
RUN chown -R builder $SCRIPT_DIR/

CMD ["/scripts/main.sh"]
