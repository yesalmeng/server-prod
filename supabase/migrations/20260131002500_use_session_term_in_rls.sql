-- Update get_current_term to use session variable set by application
CREATE OR REPLACE FUNCTION public.get_current_term()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 AS $function$
 BEGIN
   -- Prefer the term set by the application for consistency
   -- Fallback to SQL calculation only if not set (e.g. background tasks/direct SQL)
   RETURN COALESCE(
     NULLIF(current_setting('app.current_term', true), ''),
     (
       WITH la_time AS (SELECT now() AT TIME ZONE 'America/Los_Angeles' as t)
       SELECT (CASE WHEN EXTRACT(MONTH FROM t) <= 6 THEN '1H' ELSE '2H' END) || EXTRACT(YEAR FROM t)::text
       FROM la_time
     )
   );
 END;
$function$;
