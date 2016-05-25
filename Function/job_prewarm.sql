CREATE OR REPLACE FUNCTION job_prewarm()
  RETURNS text AS
$BODY$
/*
эта функция загружает нужные объекты в кэш
*/
DECLARE
    v_pages integer;
    v_relname varchar(64);
    v_percent numeric(10,2);
    v_out text = '';
BEGIN
    FOR v_relname, v_percent IN ( SELECT t.relname, t.pct_of_relation
                                  FROM
                                  (
                                   SELECT c.relname, round(100 * count(b.bufferid) * (SELECT current_setting('block_size')::int) / greatest(1,pg_relation_size(c.oid)),1) as pct_of_relation
                                   FROM pg_class as c
                                   LEFT JOIN pg_buffercache as b ON b.relfilenode = c.relfilenode AND b.reldatabase IN (0, (SELECT oid FROM pg_database WHERE datname = current_database()))
                                   WHERE c.relname IN ('<table1>', '<idx1>', '<idx2>')
                                   GROUP BY c.oid, c.relname
                                  ) as t
                                  WHERE COALESCE(t.pct_of_relation, 0.0) <> 100
                                )
    LOOP
        v_pages := (SELECT pg_prewarm(v_relname));
        RAISE LOG 'JOB pg_prewarm: in the object "%" (current%% %) loaded % pages', v_relname, v_percent, v_pages;
        v_out := v_out || 'in the object "' || v_relname || '" (current% ' || COALESCE(v_percent, 0.0) || ') loaded ' || v_pages || ' pages' || E'\n';
    END LOOP;
    --
    perform pg_stat_statements_reset(); -- сбрасываем статистику по всем запросам
    --
    RETURN v_out;
END
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
