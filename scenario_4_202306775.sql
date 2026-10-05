-- ============================================================
-- ICT371 PostgreSQL Scenario Assignment - Scenario 4: Campus Clinic Medicine Dispensing
-- Student: Augustine Lukaki      Student No: 202306775
-- Run in pgAdmin Query Tool (or psql). RAISE NOTICE output appears in the
-- "Messages" tab; run each SELECT on its own to view its result grid.
-- ============================================================

-- Clean-up so the script can be re-run safely
DROP TABLE IF EXISTS dispensing_records CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;

-- ------------------------------------------------------------
-- 1. Create tables and add sample data
-- ------------------------------------------------------------
CREATE TABLE medicines (
    medicine_id SERIAL PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id SERIAL PRIMARY KEY,
    medicine_id INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(100) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    status VARCHAR(12) NOT NULL DEFAULT 'DISPENSED'
        CHECK (status IN ('DISPENSED', 'REVERSED')),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol 500mg', 100),
    ('Amoxicillin 250mg', 12),
    ('Oral Rehydration Salts', 0);

SELECT * FROM medicines ORDER BY medicine_id;

-- ------------------------------------------------------------
-- 2. IF / ELSIF / ELSE  (out of stock / low on stock / sufficiently stocked)
-- ------------------------------------------------------------
DO $$
DECLARE
    v_id    INT := 2;   -- change this id to test the other branches
    v_name  medicines.medicine_name%TYPE;
    v_stock INT;
BEGIN
    SELECT medicine_name, stock_quantity INTO v_name, v_stock
    FROM medicines WHERE medicine_id = v_id;

    IF v_stock = 0 THEN
        RAISE NOTICE '% (% units) - OUT OF STOCK', v_name, v_stock;
    ELSIF v_stock < 20 THEN
        RAISE NOTICE '% (% units) - LOW on stock', v_name, v_stock;
    ELSE
        RAISE NOTICE '% (% units) - SUFFICIENTLY stocked', v_name, v_stock;
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
        RAISE NOTICE 'Stock review day %', v_counter;
        v_counter := v_counter + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', i;
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 4. Procedure dispense_medicine
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE dispense_medicine(p_medicine_id INT, p_person VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_qty
            USING ERRCODE = '22023';
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id;
    END IF;

    IF v_stock < p_qty THEN
        RAISE EXCEPTION 'Insufficient units: requested %, available %', p_qty, v_stock;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity - p_qty WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (medicine_id, student_number, quantity, status)
    VALUES (p_medicine_id, p_person, p_qty, 'DISPENSED');

    RAISE NOTICE 'Dispensing recorded: % x medicine % for %', p_qty, p_medicine_id, p_person;
END;
$$;

-- ------------------------------------------------------------
-- 5. Two valid requests and one request exceeding stock
-- ------------------------------------------------------------
DO $$
BEGIN
    BEGIN
        CALL dispense_medicine(1, '202301001', 20);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Request rejected: %', SQLERRM;
    END;

    BEGIN
        CALL dispense_medicine(2, '202301002', 5);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Request rejected: %', SQLERRM;
    END;

    BEGIN
        CALL dispense_medicine(2, '202301003', 20);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Request rejected: %', SQLERRM;
    END;

END $$;

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- ------------------------------------------------------------
-- 6. Procedure reverse_dispensing (safe against double processing)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_parent INT;
    v_qty    INT;
BEGIN
    -- Only an active record is updated, so a repeat call changes nothing
    UPDATE dispensing_records SET status = 'REVERSED'
    WHERE record_id = p_record_id AND status = 'DISPENSED'
    RETURNING medicine_id, quantity INTO v_parent, v_qty;

    IF NOT FOUND THEN
        RAISE NOTICE 'Record % not found or already reversed; nothing restored', p_record_id;
        RETURN;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity + v_qty WHERE medicine_id = v_parent;
    RAISE NOTICE 'Record % reversed; % units restored', p_record_id, v_qty;
END;
$$;

CALL reverse_dispensing(1);   -- first call: restores stock
CALL reverse_dispensing(1);   -- second call: must not restore again

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- ------------------------------------------------------------
-- 7. Explicit cursor (medicines below the low-stock threshold of 20)
-- ------------------------------------------------------------
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT medicine_id, medicine_name, stock_quantity
        FROM medicines
        WHERE stock_quantity < 20
        ORDER BY stock_quantity, medicine_id;
    rec RECORD;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Medicine %: % - % units left', rec.medicine_id, rec.medicine_name, rec.stock_quantity;
    END LOOP;
    CLOSE cur_low;
END $$;

-- ------------------------------------------------------------
-- 8. Invalid quantity handled with an EXCEPTION block
-- ------------------------------------------------------------
DO $$
BEGIN
    CALL dispense_medicine(1, '202301004', -3);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Invalid quantity handled: %', SQLERRM;
END $$;

-- ------------------------------------------------------------
-- 9. Final results
-- ------------------------------------------------------------
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
