module Devmetrics
  class ApplicationController < ActionController::Base
    helper ::Importmap::ImportmapTagsHelper if defined?(::Importmap::ImportmapTagsHelper)
    helper ::Turbo::FramesHelper if defined?(::Turbo::FramesHelper)

    allow_browser versions: :modern if respond_to?(:allow_browser)
    protect_from_forgery with: :exception
  end
end
