define_upgrade do
  if Partybus.config.bootstrap_server

    must_be_data_master

    # Make sure API is down
    stop_services(["nginx", "opscode-erchef"])

    start_services(["opscode-chef-mover", "elasticsearch"])

    force_restart_service("opscode-chef-mover")

    sleep 30

    log "All orgs are in the 503 mode..."
    # call 503_mode_on_all_orgs
    run_command("/opt/opscode/embedded/bin/escript " \
                "/opt/opscode/embedded/service/opscode-chef-mover/scripts/migrate " \
                "mover_org_darklaunch true")

    log "Migrating indexed search data..."
    run_command("/opt/opscode/embedded/bin/escript " \
                "/opt/opscode/embedded/service/opscode-chef-mover/scripts/migrate " \
                "mover_reindex_elasticsearch_migration_callback normal")

    stop_services(["opscode-chef-mover", "elasticsearch"])

  end
end

