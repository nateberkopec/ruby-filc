FROM ruby-filc:4.0.9
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY config.ru ./
EXPOSE 9292
CMD ["bundle", "exec", "rackup", "--server", "webrick", "--host", "0.0.0.0", "--port", "9292"]
