require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 1440 ]

  ActionController::Base.allow_forgery_protection = true

  # Chrome can report a node replaced during a page swap as this inspector error
  # instead of a stale element. Translate only that exact message, optionally followed
  # by chromedriver's session line, so Capybara retries the lookup; every other
  # UnknownError propagates unchanged.
  module DetachedNodeErrorTranslation
    DETACHED_NODE_MESSAGE = /\Aunknown error: unhandled inspector error: \{"code":-32000,"message":"Node with given id does not belong to the document"\}(?:\n\s*\(Session info: chrome=[\d.]+\))?\z/

    private

      def execute(...)
        super
      rescue Selenium::WebDriver::Error::UnknownError => e
        raise unless DETACHED_NODE_MESSAGE.match?(e.message)

        raise Selenium::WebDriver::Error::StaleElementReferenceError, e.message
      end
  end

  Selenium::WebDriver::Remote::Bridge.prepend(DetachedNodeErrorTranslation)
end
