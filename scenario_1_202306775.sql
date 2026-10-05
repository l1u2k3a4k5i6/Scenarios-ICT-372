-- ============================================================
-- ICT371 PostgreSQL Scenario Assignment - Scenario 1: University Library Book Loans
-- Student: Augustine Lukaki      Student No: 202306775
-- Run in pgAdmin Query Tool (or psql). RAISE NOTICE output appears in the
-- "Messages" tab; run each SELECT on its own to view its result grid.
-- ============================================================

-- Clean-up so the script can be re-run safely
DROP TABLE IF EXISTS book_loans CASCADE;
DROP TABLE IF EXISTS books CASCADE;

-- ------------------------------------------------------------
-- 1. Create tables and add sample data
-- ------------------------------------------------------------
CREATE TABLE books (
    book_id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    author VARCHAR(100),
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id SERIAL PRIMARY KEY,
    book_id INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(100) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    loan_status VARCHAR(12) NOT NULL DEFAULT 'BORROWED'
        CHECK (loan_status IN ('BORROWED', 'RETURNED')),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO books (title, author, available_copies) VALUES
    ('Database System Concepts', 'Silberschatz', 5),
    ('Introduction to Algorithms', 'Cormen', 2),
    ('Computer Networks', 'Tanenbaum', 0),
    ('Operating System Concepts', 'Silberschatz', 10);

SELECT * FROM books ORDER BY book_id;

-- ------------------------------------------------------------
-- 2. IF / ELSIF / ELSE  (book unavailable / low on copies / sufficiently stocked)
-- ------------------------------------------------------------
DO $$
DECLARE
    v_id    INT := 3;   -- change this id to test the other branches
    v_name  books.title%TYPE;
    v_stock INT;
BEGIN
    SELECT title, available_copies INTO v_name, v_stock
    FROM books WHERE book_id = v_id;

    IF v_stock = 0 THEN
        RAISE NOTICE '% (% copies) - UNAVAILABLE', v_name, v_stock;
    ELSIF v_stock <= 2 THEN
        RAISE NOTICE '% (% copies) - LOW on copies', v_name, v_stock;
    ELSE
        RAISE NOTICE '% (% copies) - SUFFICIENTLY stocked', v_name, v_stock;
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
        RAISE NOTICE 'Overdue reminder number %', v_counter;
        v_counter := v_counter + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', i;
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 4. Procedure borrow_book
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE borrow_book(p_book_id INT, p_person VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_qty
            USING ERRCODE = '22023';
    END IF;

    SELECT available_copies INTO v_stock
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF v_stock < p_qty THEN
        RAISE EXCEPTION 'Insufficient copies: requested %, available %', p_qty, v_stock;
    END IF;

    UPDATE books SET available_copies = available_copies - p_qty WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_person, p_qty, 'BORROWED');

    RAISE NOTICE 'Loan recorded: % x book % for %', p_qty, p_book_id, p_person;
END;
$$;

-- ------------------------------------------------------------
-- 5. Two valid requests and one request exceeding stock
-- ------------------------------------------------------------
DO $$
BEGIN
    BEGIN
        CALL borrow_book(1, '202301001', 2);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Request rejected: %', SQLERRM;
    END;

    BEGIN
        CALL borrow_book(2, '202301002', 1);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Request rejected: %', SQLERRM;
    END;

    BEGIN
        CALL borrow_book(2, '202301003', 5);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Request rejected: %', SQLERRM;
    END;

END $$;

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- ------------------------------------------------------------
-- 6. Procedure return_book (safe against double processing)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_parent INT;
    v_qty    INT;
BEGIN
    -- Only an active record is updated, so a repeat call changes nothing
    UPDATE book_loans SET loan_status = 'RETURNED'
    WHERE loan_id = p_loan_id AND loan_status = 'BORROWED'
    RETURNING book_id, quantity INTO v_parent, v_qty;

    IF NOT FOUND THEN
        RAISE NOTICE 'Record % not found or already returned; nothing restored', p_loan_id;
        RETURN;
    END IF;

    UPDATE books SET available_copies = available_copies + v_qty WHERE book_id = v_parent;
    RAISE NOTICE 'Record % returned; % copies restored', p_loan_id, v_qty;
END;
$$;

CALL return_book(1);   -- first call: restores stock
CALL return_book(1);   -- second call: must not restore again

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- ------------------------------------------------------------
-- 7. Explicit cursor (books with few copies remaining)
-- ------------------------------------------------------------
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books
        WHERE available_copies <= 2
        ORDER BY available_copies, book_id;
    rec RECORD;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Book %: % - % copies left', rec.book_id, rec.title, rec.available_copies;
    END LOOP;
    CLOSE cur_low;
END $$;

-- ------------------------------------------------------------
-- 8. Invalid quantity handled with an EXCEPTION block
-- ------------------------------------------------------------
DO $$
BEGIN
    CALL borrow_book(1, '202301004', 0);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Invalid quantity handled: %', SQLERRM;
END $$;

-- ------------------------------------------------------------
-- 9. Final results
-- ------------------------------------------------------------
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
