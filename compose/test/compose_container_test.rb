# frozen_string_literal: true

require "test_helper"
require "socket"

class Open3Stub
  def initialize(expected_up_cmd, expected_filepath)
    @expected_up_cmd = expected_up_cmd
    @expected_filepath = expected_filepath
  end

  def capture2(up_cmd, options)
    # Check if the captured arguments match the expected ones
    assert_equal @expected_up_cmd, up_cmd
    assert_equal({chdir: @expected_filepath}, options)

    # Return a dummy result (can be nil or any other value you need for testing)
    [nil, nil]
  end
end

class ComposeContainerTest < TestcontainersTest
  TEST_PATH = Dir.getwd.concat("/test")
  def before_all
    super

    @container = Testcontainers::ComposeContainer.new(filepath: TEST_PATH)
    @container.start
  end

  def after_all
    @container.stop
  end

  def test_information_spawn
    host = @container.host_process(service: "hub", port: 4444)
    port = @container.port_process(service: "hub", port: 4444)

    assert "0.0.0.0", host
    assert 4444, port
  end

  def test_can_pull_before_build_in_spawn
    container = Testcontainers::ComposeContainer.new(filepath: TEST_PATH, pull: true)
    host = container.host_process(service: "hub", port: 4444)
    port = container.port_process(service: "hub", port: 4444)

    assert "0.0.0.0", host
    assert 4444, port
  end

  def test_can_build_images_before_spawning_service_via_compose
    container = Testcontainers::ComposeContainer.new(filepath: TEST_PATH, build: true)
    mock = Minitest::Mock.new
    mock.expect(:capture2, nil, [" docker compose -f  docker-compose.yml up -d --build"], {chdir: TEST_PATH})

    Open3.stub :capture2, proc { |cmd, opts| mock.capture2(cmd, opts) } do
      container.build
      container.start
    end
    mock.verify
    container.stop
  end

  def test_can_verfy_specific_services
    services = ["hub", "firefox"]
    container = Testcontainers::ComposeContainer.new(filepath: TEST_PATH, services: services)
    mock = Minitest::Mock.new
    mock.expect(:capture2, nil, [" docker compose -f  docker-compose.yml up -d hub firefox"], {chdir: TEST_PATH})
    Open3.stub :capture2, proc { |cmd, opts| mock.capture2(cmd, opts) } do
      container.start
    end
    mock.verify
    container.stop
  end

  def test_with_specific_services
    services = ["hub", "firefox", "chrome"]
    container = Testcontainers::ComposeContainer.new(filepath: TEST_PATH, services: services)
    container.start

    assert_includes container.services, "hub"
    assert_includes container.services, "firefox"
    assert_includes container.services, "chrome"
    container.stop
  end

  def test_with_specific_compose_files
    compose_file_name = ["docker-compose.yml", "docker-compose2.yml"]
    container = Testcontainers::ComposeContainer.new(filepath: TEST_PATH, compose_file_name: compose_file_name)

    container.start

    host = container.host_process(service: "hub", port: 4444)
    port = container.port_process(service: "hub", port: 4444)

    host2 = container.host_process(service: "alpine", port: 3306)
    port2 = container.port_process(service: "alpine", port: 3306)

    assert "0.0.0.0", host
    assert 4444, port
    assert "0.0.0.0", host2
    assert 3306, port2
    container.stop
  end

  def test_logs_for_process
    container = Testcontainers::ComposeContainer.new(filepath: TEST_PATH)
    container.start
    ip_address = Socket.ip_address_list.find { |addr| addr.ipv4? && !addr.ipv4_loopback? }.ip_address
    url = "http://#{ip_address}:4444/ui"
    container.wait_for_request(url: url)
    stdout, _stderr = container.logs
    assert stdout
    container.stop
  end

  def test_can_pass_env_params
    compose_file_name = ["docker-compose3.yml"]
    container = Testcontainers::ComposeContainer.new(filepath: TEST_PATH, compose_file_name: compose_file_name, env_file: ".env.test")
    container.start
    stdout, _stderr = container.run_in_container(service_name: "alpine", command: "printenv TEST_ASSERT_KEY")
    assert_equal "successful test ", stdout.tr("\n", " ")
    container.stop
  end

  def test_compose_can_wait_for_log
    compose_file_name = ["docker-compose4.yml"]
    container = Testcontainers::ComposeContainer.new(filepath: TEST_PATH, compose_file_name: compose_file_name)
    container.start
    stdout, _stderr = container.logs
    assert_equal " Hello from Docker!", stdout.split("|")[3].split("\n")[0]
    container.stop
  end
end