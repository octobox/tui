# frozen_string_literal: true

module OctoboxTui
  module Db
    module Schema
      def self.migrate!(db)
        db.create_table?(:notifications) do
          primary_key :db_id
          Integer :id, null: false, unique: true
          String :github_id
          String :reason
          TrueClass :unread, default: true
          TrueClass :archived, default: false
          TrueClass :starred, default: false
          String :url, text: true
          String :web_url, text: true
          DateTime :last_read_at
          DateTime :created_at
          DateTime :updated_at
          String :subject_title, text: true
          String :subject_url, text: true
          String :subject_type
          String :subject_state
          String :subject_author
          Integer :repo_id
          String :repo_name
          String :repo_owner
          String :repo_url, text: true
          TrueClass :muted, default: false
          DateTime :fetched_at

          index :id, unique: true
          index :archived
          index :starred
          index :updated_at
        end

        db.create_table?(:sync_status) do
          String :resource, primary_key: true
          DateTime :last_sync
          String :error, text: true
        end

        # Migrations for existing databases
        unless db[:notifications].columns.include?(:subject_author)
          db.alter_table(:notifications) { add_column :subject_author, String }
        end
      end
    end
  end
end
