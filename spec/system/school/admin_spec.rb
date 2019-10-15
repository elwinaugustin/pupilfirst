require 'rails_helper'

feature 'School admins Editor', js: true do
  include UserSpecHelper
  include NotificationHelper

  # Setup a school with 2 school admins
  let!(:school) { create :school, :current }
  let!(:school_admin_1) { create :school_admin, school: school }
  let!(:school_admin_2) { create :school_admin, school: school }
  let(:name) { Faker::Name.name }
  let(:email) { Faker::Internet.email(name) }
  let(:name_for_edit) { Faker::Name.name }
  let(:user) { create :user }
  let(:name_for_user) { Faker::Name.name }
  let(:coach) { create :faculty, school: school }

  scenario 'school admin adds a new user as an admin' do
    sign_in_user school_admin_1.user, referer: admins_school_path

    # list all school admins
    expect(page).to have_text("Add New School Admin")
    expect(page).to have_text(school_admin_1.user.name)
    expect(page).to have_text(school_admin_2.user.name)

    # Add a new school admin
    click_button 'Add New School Admin'
    fill_in 'email', with: email
    fill_in 'name', with: name
    click_button 'Create School Admin'
    expect(page).to have_text("School Admin created successfully")
    dismiss_notification

    expect(page).to have_text(name)
    new_school_admin_user = school.users.where(email: email).first
    expect(new_school_admin_user.name).to eq(name)
    expect(new_school_admin_user.school_admin.present?).to eq(true)

    # Edit school admin
    find("a", text: new_school_admin_user.name).click
    expect(page).to have_text(new_school_admin_user.name)
    expect(page).to have_text(new_school_admin_user.email)

    fill_in 'name', with: name_for_edit
    click_button 'Update School Admin'
    expect(page).to have_text("School Admin updated successfully")
    dismiss_notification
    expect(new_school_admin_user.reload.name).to eq(name_for_edit)
  end

  scenario 'school admin adds an existing user as an admin', js: true do
    sign_in_user school_admin_1.user, referer: admins_school_path

    click_button 'Add New School Admin'
    fill_in 'email', with: user.email
    fill_in 'name', with: name_for_user
    click_button 'Create School Admin'
    expect(page).to have_text("School Admin created successfully")
    dismiss_notification

    expect(school.users.where(email: user.email).count).to eq(1)
    expect(user.reload.name).to eq(name_for_user)
  end

  scenario 'user who is not logged in tries to access school admin editor interface' do
    visit admins_school_path
    expect(page).to have_text("Please sign in to continue.")
  end

  scenario 'logged in user who not a school admin tries to access school admin editor interface' do
    sign_in_user coach.user, referer: admins_school_path
    expect(page).to have_text("The page you were looking for doesn't exist!")
  end
end
