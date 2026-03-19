require 'rails_helper'

RSpec.describe QueryLog, type: :model do
  it 'is valid with basic attributes' do
    log = QueryLog.new(
      query: 'SELECT * FROM users',
      duration: 150,
      user_id: 1
    )
    expect(log).to be_valid
  end

  it 'has query attribute' do
    log = QueryLog.new(query: 'SELECT * FROM posts')
    expect(log.query).to eq 'SELECT * FROM posts'
  end
end
