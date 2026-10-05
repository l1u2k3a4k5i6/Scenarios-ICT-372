-- ============================================================
-- ICT371 PostgreSQL Scenario Assignment - Scenario 3: Student Hostel Room Allocation
-- Student: Augustine Lukaki      Student No: 202306775
-- Run in pgAdmin Query Tool (or psql). RAISE NOTICE output appears in the
-- "Messages" tab; run each SELECT on its own to view its result grid.
-- ============================================================

-- Clean-up so the script can be re-run safely
DROP TABLE IF EXISTS allocations CASCADE;
DROP TABLE IF EXISTS hostel_rooms CASCADE;

-- ------------------------------------------------------------
-- 1. Create tables and add sample data
-- ------------------------------------------------------------
CREATE TABLE hostel_rooms (
    room_id SERIAL PRIMARY KEY,
    room_number VARCHAR(10) NOT NULL UNIQUE,
    capacity INT NOT NULL CHECK (capacity > 0),
    available_spaces INT NOT NULL,
    CHECK (available_spaces >= 0 AND available_spaces <= capacity)
);

CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY,
    room_id INT NOT NULL REFERENCES hostel_rooms(room_id),
    student_number VARCHAR(20) NOT NULL,
    status VARCHAR(12) NOT NULL DEFAULT 'ALLOCATED'
        CHECK (status IN ('ALLOCATED', 'COMPLETE')),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO hostel_rooms (room_number, capacity, available_spaces) VALUES
    ('A101', 4, 4),
    ('A102', 2, 1),
    ('B201', 3, 0);

SELECT * FROM hostel_rooms ORDER BY room_id;

-- ------------------------------------------------------------
-- 2. IF / ELSIF / ELSE  (room full / one space left / several spaces)
-- ------------------------------------------------------------
DO $$
DECLARE
    v_id     INT := 2;   -- change this id to test the other branches
    v_room   hostel_rooms.room_number%TYPE;
    v_spaces INT;
BEGIN
    SELECT room_number, available_spaces INTO v_room, v_spaces
    FROM hostel_rooms WHERE room_id = v_id;

    IF v_spaces = 0 THEN
        RAISE NOTICE 'Room % (% spaces) - FULL', v_room, v_spaces;
    ELSIF v_spaces = 1 THEN
        RAISE NOTICE 'Room % (% space) - ONE space left', v_room, v_spaces;
    ELSE
        RAISE NOTICE 'Room % (% spaces) - SEVERAL spaces available', v_room, v_spaces;
    END IF;
END $$;

-- ------------------------------------------------------------
-- 3. WHILE loop and numeric FOR loop
-- ------------------------------------------------------------
DO $$
DECLARE
    v_day INT := 1;
BEGIN
    WHILE v_day <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', v_day;
        v_day := v_day + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', i;
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 4. Procedure allocate_room
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE allocate_room(p_room_id INT, p_student VARCHAR)
LANGUAGE plpgsql
AS $$
DECLARE
    v_spaces INT;
BEGIN
    IF p_student IS NULL OR btrim(p_student) = '' THEN
        RAISE EXCEPTION 'Student number cannot be blank'
            USING ERRCODE = '22023';
    END IF;

    SELECT available_spaces INTO v_spaces
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;

    IF v_spaces < 1 THEN
        RAISE EXCEPTION 'Room % is full; no bed space available', p_room_id;
    END IF;

    UPDATE hostel_rooms SET available_spaces = available_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (room_id, student_number, status)
    VALUES (p_room_id, btrim(p_student), 'ALLOCATED');

    RAISE NOTICE 'Student % allocated to room %', btrim(p_student), p_room_id;
END;
$$;

-- ------------------------------------------------------------
-- 5. Two valid allocations and one allocation to a full room
-- ------------------------------------------------------------
DO $$
BEGIN
    BEGIN
        CALL allocate_room(1, '202301001');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Allocation rejected: %', SQLERRM;
    END;

    BEGIN
        CALL allocate_room(2, '202301002');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Allocation rejected: %', SQLERRM;
    END;

    BEGIN
        CALL allocate_room(3, '202301003');   -- room B201 is full
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Allocation rejected: %', SQLERRM;
    END;
END $$;

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- ------------------------------------------------------------
-- 6. Procedure check_out (safe against double processing)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room INT;
BEGIN
    -- Only an active allocation is updated, so a repeat call changes nothing
    UPDATE allocations SET status = 'COMPLETE'
    WHERE allocation_id = p_allocation_id AND status = 'ALLOCATED'
    RETURNING room_id INTO v_room;

    IF NOT FOUND THEN
        RAISE NOTICE 'Allocation % not found or already complete; no space freed', p_allocation_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms SET available_spaces = available_spaces + 1
    WHERE room_id = v_room;

    RAISE NOTICE 'Allocation % complete; one bed space freed in room %', p_allocation_id, v_room;
END;
$$;

CALL check_out(1);   -- first call: frees one space
CALL check_out(1);   -- second call: must not free another space

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- ------------------------------------------------------------
-- 7. Explicit cursor (full or nearly full rooms)
-- ------------------------------------------------------------
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_id, room_number, available_spaces
        FROM hostel_rooms
        WHERE available_spaces <= 1
        ORDER BY available_spaces, room_id;
    rec RECORD;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Room % - % space(s) left', rec.room_number, rec.available_spaces;
    END LOOP;
    CLOSE cur_rooms;
END $$;

-- ------------------------------------------------------------
-- 8. Blank student number handled with an EXCEPTION block
-- ------------------------------------------------------------
DO $$
BEGIN
    CALL allocate_room(1, '   ');
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Invalid input handled: %', SQLERRM;
END $$;

-- ------------------------------------------------------------
-- 9. Final results
-- ------------------------------------------------------------
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
