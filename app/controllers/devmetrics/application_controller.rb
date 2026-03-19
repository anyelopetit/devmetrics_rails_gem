module Devmetrics
  class ApplicationController < ActionController::Base
    helper ::Importmap::ImportmapTagsHelper
    helper ::Turbo::FramesHelper

    allow_browser versions: :modern
    protect_from_forgery with: :exception
  end
end
