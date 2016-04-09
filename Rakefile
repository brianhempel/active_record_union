require 'bundler/gem_tasks'

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)
task :default => :spec

module TestTasks
  module_function

  TEST_CMD = 'bundle exec rspec'

  def run_all(envs, cmd = "bundle install --quiet && #{TEST_CMD}", success_message)
    statuses = envs.map { |env| run(env, cmd) }
    failed   = statuses.reject(&:first).map(&:last)
    if failed.empty?
      $stderr.puts success_message
    else
      $stderr.puts "❌  FAILING (#{failed.size}):\n#{failed.map { |env| to_bash_cmd_with_env(cmd, env) } * "\n"}"
      exit 1
    end
  end

  def run(env, cmd)
    require 'pty'
    require 'English'
    Bundler.with_clean_env do
      $stderr.puts to_bash_cmd_with_env(cmd, env)
      PTY.spawn(env, cmd) do |r, _w, pid|
        begin
          r.each_line { |l| puts l }
        rescue Errno::EIO
          # Errno:EIO error means that the process has finished giving output.
          next
        ensure
          ::Process.wait pid
        end
      end
      [$CHILD_STATUS && $CHILD_STATUS.exitstatus == 0, env]
    end
  end

  def gemfiles
    Dir.glob('./spec/gemfiles/*.gemfile').sort
  end

  def to_bash_cmd_with_env(cmd, env)
    "(export #{env.map { |k, v| "#{k}=#{v}" }.join(' ')}; #{cmd})"
  end
end

desc 'Test all Gemfiles from spec/*.gemfile'
task :test_all_gemfiles do
  envs = TestTasks.gemfiles.map { |gemfile| { 'BUNDLE_GEMFILE' => gemfile } }
  TestTasks.run_all envs, "✓ Tests pass with all #{envs.size} gemfiles"
end
