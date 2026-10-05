-- ============================================================
-- ICT371 PostgreSQL Scenario Assignment - Scenario 2: Computer Laboratory Reservations
-- Student: Augustine Lukaki      Student No: 202306775
-- Run in pgAdmin Query Tool (or psql). RAISE NOTICE output appears in the
-- "Messages" tab; run each SELECT on its own to view its result grid.
-- ============================================================

-- Clean-up so the script can be re-run safely
DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;

-- ------------------------------------------------------------
-- 1. Create tables and add sample data
-- ------------------------------------------------------------
CREATE TABLE lab_sessions (
    session_id SERIAL PRIMARY KEY,
    session_name VARCHAR(100) NOT NULL,
    total_workstations INT NOT NULL DEFAULT 30,
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    session_id INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer VARCHAR(100) NOT NULL,
    workstations INT NOT NULL CHECK (workstations > 0),
    status VARCHAR(12) NOT NULL DEFAULT 'RESERVED'
        CHECK (status IN ('RESERVED', 'CANCELLED')),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO lab_sessions (session_name, total_workstations, available_workstations) VALUES
    ('Session 1 - Database Lab', 30, 30),
    ('Session 2 - Networking Lab', 30, 8),
    ('Session 3 - Programming Lab', 30, 0);

SELECT * FROM lab_sessions ORDER BY session_id;

-- ------------------------------------------------------------
-- 2. IF / ELSIF / ELSE  (session full / nearly full / enough workstations)
-- ------------------------------------------------------------
DO $$
DECLARE
    v_id    INT := 2;   -- change this id to test the other branches
    v_name  lab_sessions.session_name%TYPE;
    v_stock INT;
BEGIN
    SELECT session_name, available_workstations INTO v_name, v_stock
    FROM lab_sessions WHERE session_id = v_id;

    IF v_stock = 0 THEN
        RAISE NOTICE '% (% workstations) - FULL', v_name, v_stock;
    ELSIF v_stock <= 5 THEN
        RAISE NOTICE '% (% workstations) - NEARLY FULL', v_name, v_stock;
    ELSE
        RAISE NOTICE '% (% workstations) - has ENOUGH workstations', v_name, v_stock;
    END IF;
END $$;

-- ------------------------------------------------------------
-- 3. WHILE loop and numeric FOR loop
-- ------------------------------------------------------------
DO $$
DECLARE
    v_counter INT := 1;
BEGIN
    WHILE v_counter <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', v_counter;
        v_counter := v_counter + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', i;
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 4. Procedure reserve_workstations
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE reserve_workstations(p_session_id INT, p_person VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_qty
            USING ERRCODE = '22023';
    END IF;

    SELECT available_workstations INTO v_stock
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF v_stock < p_qty THEN
        RAISE EXCEPTION 'Insufficient workstations: requested %, available %', p_qty, v_stock;
    END IF;

    UPDATE lab_sessions SET available_workstations = available_workstations - p_qty WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations, status)
    VALUES (p_session_id, p_person, p_qty, 'RESERVED');

    RAISE NOTICE 'Reservation recorded: % x session % for %', p_qty, p_session_id, p_person;
END;
$$;

-- ------------------------------------------------------------
-- 5. Two valid requests and one request exceeding stock
-- ------------------------------------------------------------
DO $$
BEGIN
    BEGIN
        CALL reserve_workstations(1, 'Dr. Banda', 10);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Request rejected: %', SQLERRM;
    END;

    BEGIN
        CALL reserve_workstations(2, 'Mr. Phiri', 5);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Request rejected: %', SQLERRM;
    END;

    BEGIN
        CALL reserve_workstations(2, 'Ms. Mwansa', 10);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Request rejected: %', SQLERRM;
    END;

END $$;

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- ------------------------------------------------------------
-- 6. Procedure cancel_reservation (safe against double processing)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_parent INT;
    v_qty    INT;
BEGIN
    -- Only an active record is updated, so a repeat call changes nothing
    UPDATE reservations SET status = 'CANCELLED'
    WHERE reservation_id = p_reservation_id AND status = 'RESERVED'
    RETURNING session_id, workstations INTO v_parent, v_qty;

    IF NOT FOUND THEN
        RAISE NOTICE 'Record % not found or already cancelled; nothing restored', p_reservation_id;
        RETURN;
    END IF;

    UPDATE lab_sessions SET available_workstations = available_workstations + v_qty WHERE session_id = v_parent;
    RAISE NOTICE 'Record % cancelled; % workstations restored', p_reservation_id, v_qty;
END;
$$;

CALL cancel_reservation(1);   -- first call: restores stock
CALL cancel_reservation(1);   -- second call: must not restore again

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- ------------------------------------------------------------
-- 7. Explicit cursor (sessions with few workstations remaining)
-- ------------------------------------------------------------
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions
        WHERE available_workstations <= 5
        ORDER BY available_workstations, session_id;
    rec RECORD;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Session %: % - % workstations left', rec.session_id, rec.session_name, rec.available_workstations;
    END LOOP;
    CLOSE cur_low;
END $$;

-- ------------------------------------------------------------
-- 8. Invalid quantity handled with an EXCEPTION block
-- ------------------------------------------------------------
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Banda', 0);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Invalid quantity handled: %', SQLERRM;
END $$;

-- ------------------------------------------------------------
-- 9. Final results
-- ------------------------------------------------------------
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
