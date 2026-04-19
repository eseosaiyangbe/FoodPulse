FROM ruby:2.7-bullseye

# ---------------------------
# System dependencies
# ---------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        curl \
        ca-certificates \
        pkg-config && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------
# App code
# ---------------------------
WORKDIR /app

COPY *.rb ./
COPY Gemfile Gemfile
COPY modules modules

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV RACK_ENV=production

# ---------------------------
# Gems (Ruby 2.7-compatible pins)
# ---------------------------
RUN gem install sinatra -v "2.0.5"           --no-document && \
    gem install redis   -v "4.1.0"           --no-document && \
    gem install pg      -v "1.2.3"           --no-document && \
    gem install aws-sdk-dynamodb -v "1.46.0" --no-document

# ---------------------------
# Entrypoint
# ---------------------------
WORKDIR /
COPY startup.sh /startup.sh
RUN chmod +x /startup.sh

CMD ["/startup.sh"]
