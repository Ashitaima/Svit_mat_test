MAX_BATCH = 100
SERVER_ONLY = {"order_created", "payment_succeeded", "payment_failed"}


def ingest(request):

    body = parse_json(request.body)                
    if "events" not in body:
        return response(400, {"error": "events is required"})
    if len(body["events"]) == 0:
        return response(400, {"error": "events must not be empty"})
    if len(body["events"]) > MAX_BATCH:
        return response(413, {"error": "max 100 events per request"})

    valid, rejected = [], []
    for i, event in enumerate(body["events"]):
        errors = validate(event, schema_for(event.get("event_type")))


        if event.get("event_type") in SERVER_ONLY and not request.has_server_api_key:
            errors.append("event_type is allowed only from backend")

        if errors:
            rejected.append({"index": i, "errors": errors})
        else:
            valid.append(event)

    upsert_sessions(valid)
    inserted = db.insert_events(
        valid,
        on_conflict="(event_id, occurred_at) DO NOTHING",   
    )

    return response(202, {
        "accepted": inserted,
        "duplicates": len(valid) - inserted,
        "rejected": rejected,
    })
